import XCTest
#if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import CoreVideo
import QuartzCore
import UIKit
#endif
@testable import Fotty

/// Shared opt-in physical proof, never a fixture publisher or playback owner.
#if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
@MainActor
enum ReviewedAddonPhysicalCanary {
    enum Source: Equatable, Sendable { case plavio, cnc, flix, connection
        var label: String {
            switch self {
            case .plavio: "Plavio"
            case .cnc: "CNC"
            case .flix: "Flix"
            case .connection: "Source connection"
            }
        }
        var maximumSeconds: TimeInterval { 140 }
        var holdSeconds: TimeInterval { 90 }
        var minimumHoldProgress: TimeInterval { 80 }
    }
    static func run(on testCase: XCTestCase, source: Source, flixVariant: Int = 1,
        verifiedSession: StreamSession? = nil,
        evidence: @escaping @MainActor ([String: String]) -> Void = { _ in }) async throws {
        guard (1...6).contains(flixVariant) else {
            throw XCTSkip("The test variant is outside the reviewed FS1–FS6 range; no playback pass.")
        }
        let overallDeadline = ProcessInfo.processInfo.systemUptime + source.maximumSeconds
        let operation = Task { @MainActor in
            let startedAt = ProcessInfo.processInfo.systemUptime
            var prepared: NativePlaybackPreparation.Delivery?
            var player: AVPlayer?
            var item: AVPlayerItem?
            var output: AVPlayerItemVideoOutput?
            var testSurface: UIView?
            var playerLayer: AVPlayerLayer?
            let displayClock = ReviewedAddonCanaryDisplayClock()
            var phase = "catalog_fetch"
            var decodedFrames = 0
            var outputPolls = 0
            var numericOutputTimes = 0
            var newBufferSignals = 0
            var nonNilPixelBuffers = 0
            var finiteDisplayTimes = 0
            var videoTrackCount = -1
            var enabledVideoTrackCount = -1
            var lastPixelWidth = 0
            var lastPixelHeight = 0
            var firstFrame: Double?
            var firstDecodedAt: Double?
            var lastFrame: Double?
            var holdStartFrame: Double?
            @MainActor func recordEvidence(outcome: String, error: Error? = nil) {
                var safe = ["canary_scope": "source_adapter_relay_decoder", "canary_outcome": outcome,
                    "canary_phase": phase, "decoded_frame_count": String(decodedFrames),
                    "canary_source_label": source == .flix ? "FS\(flixVariant)" : source.label,
                    "item_status": String(item?.status.rawValue ?? -1),
                    "player_time_control_status": String(player?.timeControlStatus.rawValue ?? -1),
                    "relay_present": String(prepared?.proxy != nil),
                    "output_poll_count": String(outputPolls), "numeric_output_time_count": String(numericOutputTimes),
                    "new_buffer_signal_count": String(newBufferSignals), "non_nil_pixel_buffer_count": String(nonNilPixelBuffers),
                    "finite_display_time_count": String(finiteDisplayTimes),
                    "asset_video_track_count": String(videoTrackCount), "enabled_video_track_count": String(enabledVideoTrackCount),
                    "last_pixel_width": String(lastPixelWidth), "last_pixel_height": String(lastPixelHeight),
                    "layer_ready_for_display": String(playerLayer?.isReadyForDisplay ?? false),
                    "surface_in_window": String(testSurface?.window != nil),
                    "display_link_tick_count": String(displayClock.tickCount),
                    "required_hold_seconds": String(Int(source.holdSeconds)),
                    "required_hold_progress_seconds": String(Int(source.minimumHoldProgress)),
                    "maximum_canary_seconds": String(Int(source.maximumSeconds))]
                func finite(_ value: Double?) -> String? {
                    guard let value, value.isFinite, abs(value) <= 1_000_000_000 else { return nil }
                    return String(format: "%.3f", value)
                }
                safe["elapsed_seconds"] = finite(ProcessInfo.processInfo.systemUptime - startedAt)
                safe["decoded_startup_seconds"] = firstDecodedAt.flatMap { finite($0 - startedAt) }
                safe["player_time_seconds"] = finite(player?.currentTime().seconds)
                safe["player_rate"] = finite(player.map { Double($0.rate) })
                safe["presentation_width"] = finite(item.map { Double($0.presentationSize.width) })
                safe["presentation_height"] = finite(item.map { Double($0.presentationSize.height) })
                safe["decoded_progress_seconds"] = firstFrame.flatMap { first in
                    lastFrame.flatMap { finite($0 - first) }
                }
                safe["hold_progress_seconds"] = holdStartFrame.flatMap { start in
                    lastFrame.flatMap { finite($0 - start) }
                }
                if let error {
                    let underlying = (error as? PlaybackPreparationFailure)?.underlyingError ?? error
                    safe.merge(PlayerDiagnosticService().snapshot(error: underlying, trigger: .itemStatusFailed).qualityDetails) { _, new in new }
                    safe.merge((error as? PlaybackPreparationFailure)?.qualityDetails ?? [:]) { _, new in new }
                    if source == .flix, let addonError = error as? CommunitySportsAddonError {
                        safe.merge(LiveStreamResolver.communitySportsFailure(from: addonError,
                            providerName: "FS").redactedMetadata) { _, new in new }
                    }
                }
                safe.merge(prepared?.proxy?.diagnosticDetails() ?? [:]) { _, new in new }
                evidence(safe)
                let text = safe.keys.sorted().map { "\($0)=\(safe[$0]!)" }.joined(separator: "\n")
                let attachment = XCTAttachment(string: text)
                attachment.name = source.label + " reviewed-addon decoder evidence"
                attachment.lifetime = .keepAlways
                testCase.add(attachment)
                print("\(source.label) physical decoder canary evidence \(safe)")
            }
            defer {
                displayClock.stop()
                player?.pause()
                if let item, let output { item.remove(output) }
                player?.replaceCurrentItem(with: nil)
                playerLayer?.player = nil
                playerLayer?.removeFromSuperlayer()
                testSurface?.removeFromSuperview()
                prepared?.discard()
            }
            do {
                let selectedSession: StreamSession
                if let verifiedSession {
                    selectedSession = verifiedSession
                } else { switch source {
                case .connection:
                    throw NSError(domain: "FottyReviewedAddonCanary", code: 1010)
                case .plavio:
                let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T11:30:00Z")!
                let now = Date()
                guard kickoff >= now.addingTimeInterval(-3 * 3600), kickoff <= now.addingTimeInterval(120) else {
                    throw XCTSkip("The verified Aston Villa–Manchester City fixture is outside the one-off canary window; no playback pass.")
                }
                // Test request from the independently verified dated fixture.
                // The real adapter still validates current catalog/date/teams;
                // no fixture is inserted and no encoded source ID is decoded.
                let lookup = StreamPlaybackRequest(matchID: "reviewed-football-canary:2026-10-24:villa-city",
                    displayTitle: "Aston Villa vs Manchester City", homeTeam: "Aston Villa",
                    awayTeam: "Manchester City", category: "football", kickoffDate: kickoff)
                let sessions: [StreamSession]
                phase = "stream_resolution"
                do { sessions = try await PlavioSportsAddonClient().resolve(for: lookup) }
                catch let error as CommunitySportsAddonError {
                    switch error {
                    case .matchNotFound, .streamEntriesEmpty, .streamAdmissionRejected:
                        throw XCTSkip("Current reviewed fixture has no admitted additional-source delivery; no playback pass.")
                    default: throw error
                    }
                }
                guard let session = sessions.first(where: {
                    $0.diagnosticMetadata["source_family"] == PlavioSportsAddonClient.providerCode
                        && $0.streamType == .hls && $0.requiredHeaders.isEmpty && $0.requiresLocalProxy
                        && $0.nativeOriginProfile == nil && $0.nativePlaylistProfile == nil
                }) else {
                    throw XCTSkip("No headerless, guarded-relay AS session was admitted; no playback pass.")
                }
                selectedSession = session
                case .cnc:
                let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00Z")!
                let now = Date()
                guard kickoff >= now.addingTimeInterval(-3 * 3600), kickoff <= now.addingTimeInterval(120) else {
                    throw XCTSkip("The verified Blackhawks–Canadiens fixture is outside the one-off canary window; no playback pass.")
                }
                // Test request from the explicitly verified dated NHL fixture.
                // The real adapter still validates current catalog/meta evidence;
                // no fixture is inserted and no encoded source ID is decoded.
                let lookup = StreamPlaybackRequest(matchID: "reviewed-nhl-canary:2026-10-24:chi-mtl",
                    displayTitle: "Chicago Blackhawks vs Montreal Canadiens", homeTeam: "Chicago Blackhawks",
                    awayTeam: "Montreal Canadiens", category: "hockey", kickoffDate: kickoff)
                phase = "stream_resolution"
                let sessions: [StreamSession]
                do { sessions = try await CNCSportsAddonClient.shared.resolve(for: lookup) }
                catch let error as CommunitySportsAddonError {
                    switch error {
                    case .matchNotFound, .streamEntriesEmpty, .streamAdmissionRejected:
                        throw XCTSkip("Current reviewed CNC fixture has no admitted delivery; no playback pass.")
                    default: throw error
                    }
                }
                guard let session = sessions.first(where: {
                    $0.diagnosticMetadata["source_family"] == CNCSportsAddonClient.providerCode
                        && $0.providerName.hasPrefix("LS") && $0.streamType == .hls && $0.requiresLocalProxy
                        && $0.nativeOriginProfile == nil && $0.nativePlaylistProfile == nil
                }) else { throw XCTSkip("No guarded-relay LS session was admitted by the real adapter; no playback pass.") }
                selectedSession = session
                case .flix:
                let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T18:45:00Z")!
                let now = Date()
                guard kickoff >= now.addingTimeInterval(-3 * 3600), kickoff <= now.addingTimeInterval(120) else {
                    throw XCTSkip("The independently verified Lazio–Parma fixture is outside the one-off canary window; no playback pass.")
                }
                // This proves only general football transport compatibility,
                // never Premier League, Champions League or cricket coverage.
                // The adapter still requires a fresh, exact dated catalog row.
                let lookup = StreamPlaybackRequest(matchID: "reviewed-flix-canary:2026-10-24:lazio-parma",
                    displayTitle: "Lazio vs Parma", homeTeam: "Lazio", awayTeam: "Parma",
                    category: "football", kickoffDate: kickoff)
                phase = "stream_resolution"
                let sessions: [StreamSession]
                do { sessions = try await FlixStreamsAddonClient.shared.resolve(for: lookup) }
                catch let error as CommunitySportsAddonError {
                    switch error {
                    case .matchNotFound:
                        throw XCTSkip("The real Flix catalog did not match the verified fixture; no playback pass.")
                    case .streamEntriesEmpty:
                        throw XCTSkip("The matched Flix fixture returned no stream entries; no playback pass.")
                    case .streamAdmissionRejected(let count):
                        throw XCTSkip("The matched Flix fixture returned \(count) entries but no admitted delivery; no playback pass.")
                    default: throw error
                    }
                }
                guard let session = sessions.first(where: {
                    $0.diagnosticMetadata["source_family"] == FlixStreamsAddonClient.providerCode
                        && $0.providerName == "FS\(flixVariant)" && $0.streamType == .hls
                        && $0.requiredHeaders.isEmpty && $0.requiresLocalProxy
                        && $0.nativeOriginProfile == nil && $0.nativePlaylistProfile == nil
                }) else { throw XCTSkip("No headerless, guarded-relay FS session was admitted; no playback pass.") }
                selectedSession = session
                }
                }
                let session = selectedSession
                try Task.checkCancellation()
                phase = "relay_preparation"
                prepared = try await NativePlaybackPreparation.prepareDelivery(url: session.playableURL,
                    headers: session.requiredHeaders, cookies: [], requiresRelay: session.requiresLocalProxy,
                    originProfile: session.nativeOriginProfile, playlistProfile: session.nativePlaylistProfile)
                guard let prepared, !session.requiresLocalProxy || (prepared.proxy != nil && prepared.url.host == "127.0.0.1") else {
                    throw NSError(domain: "FottyReviewedAddonCanary", code: 1003)
                }
                phase = "item_preparation"
                let nativeItem = NativePlaybackPreparation.makeItem(url: prepared.url, headers: [:], session: session, evidence: nil)
                item = nativeItem
                let video = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
                output = video; nativeItem.add(video)
                let nativePlayer = AVPlayer(playerItem: nativeItem)
                player = nativePlayer; nativePlayer.isMuted = true; nativePlayer.volume = 0
                guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows)
                    .first(where: { !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 32 && $0.bounds.height > 32 }) else {
                    throw XCTSkip("No visible foreground test-host window is available; no decoded-video pass.")
                }
                let width = min(720, window.bounds.width - 32)
                let height = min(width * 9 / 16, window.bounds.height - 32)
                let surface = UIView(frame: CGRect(x: (window.bounds.width - width) / 2,
                    y: (window.bounds.height - height) / 2, width: width, height: height))
                surface.backgroundColor = .black
                surface.accessibilityIdentifier = "fotty-reviewed-addon-canary-surface"
                let layer = AVPlayerLayer(player: nativePlayer)
                layer.frame = surface.bounds; layer.videoGravity = .resizeAspect
                surface.layer.addSublayer(layer); window.addSubview(surface)
                testSurface = surface; playerLayer = layer
                displayClock.start()
                nativePlayer.play()

                @MainActor func decodedTime() -> Double? {
                    outputPolls += 1
                    // Apple's output clock maps the next display refresh into
                    // this item's timebase; currentTime isn't a render deadline.
                    let time = video.itemTime(forHostTime: displayClock.targetHostTime ?? CACurrentMediaTime())
                    guard time.isNumeric else { return nil }
                    numericOutputTimes += 1
                    guard video.hasNewPixelBuffer(forItemTime: time) else { return nil }
                    newBufferSignals += 1
                    if #available(iOS 26.0, *) {
                        let frame = video.pixelBufferAndDisplayTime(forItemTime: time)
                        guard let buffer = frame.pixelBuffer else { return nil }
                        nonNilPixelBuffers += 1
                        let size = buffer.withUnsafeBuffer { (CVPixelBufferGetWidth($0), CVPixelBufferGetHeight($0)) }
                        lastPixelWidth = size.0; lastPixelHeight = size.1
                        let seconds = frame.itemTimeForDisplay.seconds
                        if seconds.isFinite { finiteDisplayTimes += 1 }
                        return size.0 > 0 && size.1 > 0 && seconds.isFinite ? seconds : nil
                    } else {
                        var displayed = CMTime.invalid
                        guard let buffer = video.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayed) else { return nil }
                        nonNilPixelBuffers += 1
                        lastPixelWidth = CVPixelBufferGetWidth(buffer); lastPixelHeight = CVPixelBufferGetHeight(buffer)
                        guard lastPixelWidth > 0, lastPixelHeight > 0, displayed.seconds.isFinite else { return nil }
                        finiteDisplayTimes += 1
                        return displayed.seconds
                    }
                }
                let startupDeadline = min(ProcessInfo.processInfo.systemUptime + 40, overallDeadline - source.holdSeconds)
                phase = "decoded_startup"
                var inspectedTracks = false
                while ProcessInfo.processInfo.systemUptime < startupDeadline {
                    try Task.checkCancellation()
                    if nativeItem.status == .failed {
                        throw nativeItem.error ?? NSError(domain: "FottyReviewedAddonCanary", code: 1004)
                    }
                    if nativeItem.status == .readyToPlay, !inspectedTracks {
                        inspectedTracks = true
                        enabledVideoTrackCount = nativeItem.tracks.filter { $0.isEnabled && $0.assetTrack?.mediaType == .video }.count
                        // Unknown remains -1 if metadata cannot be loaded. An
                        // absent value must not be relabelled as audio-only.
                        if let tracks = try? await nativeItem.asset.loadTracks(withMediaType: .video) { videoTrackCount = tracks.count }
                    }
                    if let seconds = decodedTime(), lastFrame == nil || seconds > lastFrame! {
                        if firstFrame == nil { firstFrame = seconds; firstDecodedAt = ProcessInfo.processInfo.systemUptime }
                        lastFrame = seconds; decodedFrames += 1
                        if decodedFrames >= 3, seconds - firstFrame! >= 2 { break }
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard decodedFrames >= 3, let first = firstFrame, let holdFrame = lastFrame,
                      holdFrame - first >= 2 else {
                    throw nativeItem.error ?? NSError(domain: "FottyReviewedAddonCanary", code: 1005)
                }
                phase = "advancing_hold"
                holdStartFrame = holdFrame
                let holdStart = ProcessInfo.processInfo.systemUptime
                var lastProgressAt = holdStart
                while ProcessInfo.processInfo.systemUptime - holdStart < source.holdSeconds {
                    try Task.checkCancellation()
                    if nativeItem.status == .failed {
                        throw nativeItem.error ?? NSError(domain: "FottyReviewedAddonCanary", code: 1006)
                    }
                    if let seconds = decodedTime(), seconds > (lastFrame ?? -.infinity) {
                        lastFrame = seconds; decodedFrames += 1
                        lastProgressAt = ProcessInfo.processInfo.systemUptime
                    }
                    guard ProcessInfo.processInfo.systemUptime - lastProgressAt <= 5 else {
                        throw nativeItem.error ?? NSError(domain: "FottyReviewedAddonCanary", code: 1007)
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard let lastFrame, lastFrame - holdFrame >= source.minimumHoldProgress else {
                    throw NSError(domain: "FottyReviewedAddonCanary", code: 1008)
                }
                phase = "completed"
                recordEvidence(outcome: "passed")
            } catch let skip as XCTSkip {
                recordEvidence(outcome: "skipped")
                throw skip
            } catch {
                recordEvidence(outcome: "failed", error: error)
                // XCTest must not print an original NSError's private userInfo,
                // localized description, signed URL, response body or error log.
                throw NSError(domain: "FottyReviewedAddonCanary", code: 1009)
            }
        }
        // Cancelling a sleeping Task throws during teardown, which can obscure
        // XCTest's actual startup failure location. A cancelled work item does
        // not throw, while the operation still owns its ordinary cancellation.
        let watchdog = DispatchWorkItem { operation.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + source.maximumSeconds, execute: watchdog)
        defer { watchdog.cancel(); operation.cancel() }
        try await operation.value
    }
}

/// Test-owned display clock. It never changes the app's playback controllers.
@MainActor
private final class ReviewedAddonCanaryDisplayClock: NSObject {
    private var link: CADisplayLink?
    private(set) var targetHostTime: CFTimeInterval?
    private(set) var tickCount = 0
    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func tick(_ link: CADisplayLink) { targetHostTime = link.targetTimestamp; tickCount += 1 }
    func stop() { link?.invalidate(); link = nil; targetHostTime = nil }
}
#endif

final class CNCSportsPhysicalCanaryTests: XCTestCase {
    @MainActor
    func testReviewedCNCDeliveryDecodesThroughGuardedRelayOnPhysicalDevice() async throws {
        #if FOTTY_REVIEWED_ADDON_CANARY && os(iOS) && !targetEnvironment(macCatalyst)
        try await ReviewedAddonPhysicalCanary.run(on: self, source: .cnc)
        #else
        throw XCTSkip("Requires the explicit FOTTY_REVIEWED_ADDON_CANARY flag on a physical iOS device; no playback pass.")
        #endif
    }
}
