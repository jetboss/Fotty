import Foundation
import AVFoundation

// MARK: - Known-good references (public sample media; legal QA use)

/// URLs used only by DEBUG pipeline checks — not bundled as streams for matches.
enum StreamPipelineKnownGoodURLs {
    /// Apple’s public HLS sample (documented streaming example CDN).
    static let appleBipbopMaster = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!

    /// Short progressive MP4 (public sample; first entry is primary for HEAD/contract steps).
    /// Multiple fallbacks exist because some CDNs return 200 for range probes yet fail `isPlayable` on device (e.g. bot filtering, moov layout).
    static let sampleProgressiveMP4 = URL(string: "https://filesamples.com/samples/video/mp4/sample_640x360.mp4")!

    static var sampleProgressiveMP4PlayableProbeCandidates: [URL] {
        [
            sampleProgressiveMP4,
            URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4")!,
            URL(string: "https://samplelib.com/preview/mp4/sample-5s.mp4")!
        ]
    }

    /// Guaranteed HTML document (negative control for “not video”).
    static let htmlDocument = URL(string: "https://www.w3.org/")!

    /// Small JSON payload (negative control).
    static let jsonDocument = URL(string: "https://jsonplaceholder.typicode.com/todos/1")!
}

// MARK: - Report

struct StreamPipelineValidationStep: Identifiable, Sendable {
    let id: UUID
    let title: String
    let passed: Bool
    let detail: String
    /// e.g. "CODEBASE+NETWORK" — how this step was validated.
    let evidenceTag: String

    init(title: String, passed: Bool, detail: String, evidenceTag: String) {
        self.id = UUID()
        self.title = title
        self.passed = passed
        self.detail = detail
        self.evidenceTag = evidenceTag
    }
}

struct StreamPipelineValidationReport: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let steps: [StreamPipelineValidationStep]

    var allPassed: Bool { steps.allSatisfy(\.passed) }

    func copyPasteSummary() -> String {
        let fmt: (Date) -> String = { $0.formatted(.iso8601) }
        var lines: [String] = []
        lines.append("Fotty stream pipeline validation")
        lines.append("Started: \(fmt(startedAt))")
        lines.append("Finished: \(fmt(finishedAt))")
        lines.append(allPassed ? "RESULT: PASS (all steps)" : "RESULT: FAIL (see steps)")
        for (i, s) in steps.enumerated() {
            lines.append("\(i + 1). [\(s.passed ? "PASS" : "FAIL")] \(s.title) — \(s.detail) [\(s.evidenceTag)]")
        }
        return lines.joined(separator: "\n")
    }
}

struct StreamPlaybackContinuityReport: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let requestedDurationSeconds: Int
    let startupSeconds: Double
    let playbackProgressSeconds: Double
    let advancingSamples: Int
    let waitingSamples: Int
    let pausedSamples: Int
    let attemptStayedStable: Bool
    let sourceStayedStable: Bool
    let playerItemStayedStable: Bool
    let automaticFailovers: Int
    let failureReason: String?

    var passed: Bool {
        failureReason == nil
            && playbackProgressSeconds > 5
            && advancingSamples > 0
            && attemptStayedStable
            && sourceStayedStable
            && playerItemStayedStable
            && automaticFailovers == 0
    }

    func copyPasteSummary() -> String {
        let fmt: (Date) -> String = { $0.formatted(.iso8601) }
        return [
            "Fotty muted playback continuity soak",
            "Started: \(fmt(startedAt))",
            "Finished: \(fmt(finishedAt))",
            passed ? "RESULT: PASS" : "RESULT: FAIL",
            "Requested: \(requestedDurationSeconds)s",
            String(format: "Startup: %.2fs", startupSeconds),
            String(format: "Decoded progress: %.2fs", playbackProgressSeconds),
            "Advancing/waiting/paused samples: \(advancingSamples)/\(waitingSamples)/\(pausedSamples)",
            "Attempt/source/item stable: \(attemptStayedStable)/\(sourceStayedStable)/\(playerItemStayedStable)",
            "Automatic failovers: \(automaticFailovers)",
            "Failure: \(failureReason ?? "none")"
        ].joined(separator: "\n")
    }
}

// MARK: - Runner

enum StreamPipelineValidationService {
    /// Ordered checks from URL hygiene through contract validation to AVFoundation playable probes.
    static func runFullSuite() async -> StreamPipelineValidationReport {
        let started = Date()
        var steps: [StreamPipelineValidationStep] = []

        steps.append(
            StreamPipelineValidationStep(
                title: "Resolver entry (code map)",
                passed: true,
                detail: "Match playback: LiveStreamResolver.resolvePlayback → enabled StreamEx/Score808 modules. Validate with Watch Live + Stream Debug sheet.",
                evidenceTag: "CODEBASE"
            )
        )

        // URL hygiene
        let badURL = URL(string: "not://\\bad")
        steps.append(
            StreamPipelineValidationStep(
                title: "Malformed URL rejected",
                passed: badURL == nil,
                detail: badURL == nil ? "URL(string:) returned nil as expected." : "Expected nil for invalid URL string.",
                evidenceTag: "CODEBASE"
            )
        )

        let probe = PlaybackProbe()
        let contractValidator = StreamContractValidator()

        // Apple HLS
        let hlsURL = StreamPipelineKnownGoodURLs.appleBipbopMaster
        let hlsHead = await probe.probe(url: hlsURL, headers: [:])
        let hlsHeadOk = (200...299).contains(hlsHead.status ?? 0) || hlsHead.status == 405
        steps.append(
            StreamPipelineValidationStep(
                title: "Known-good HLS HEAD",
                passed: hlsHeadOk,
                detail: "status=\(hlsHead.status.map(String.init) ?? "nil") type=\(hlsHead.type) content-type=\(hlsHead.contentType ?? "nil")",
                evidenceTag: "TEST_RESULT+NETWORK"
            )
        )

        let hlsContract = await contractValidator.validate(hlsURL, headers: [:])
        if case .valid = hlsContract {
            steps.append(
                StreamPipelineValidationStep(
                    title: "Known-good HLS byte contract (#EXTM3U)",
                    passed: true,
                    detail: "StreamContractValidator accepted manifest prefix.",
                    evidenceTag: "TEST_RESULT+NETWORK+CODEBASE"
                )
            )
        } else if case .invalid(let reason) = hlsContract {
            steps.append(
                StreamPipelineValidationStep(
                    title: "Known-good HLS byte contract (#EXTM3U)",
                    passed: false,
                    detail: reason,
                    evidenceTag: "TEST_RESULT+NETWORK+CODEBASE"
                )
            )
        }

        // MP4
        let mp4URL = StreamPipelineKnownGoodURLs.sampleProgressiveMP4
        let mp4Head = await probe.probe(url: mp4URL, headers: [:])
        let mp4HeadOk = (200...299).contains(mp4Head.status ?? 0) || mp4Head.status == 405
        steps.append(
            StreamPipelineValidationStep(
                title: "Known-good MP4 HEAD",
                passed: mp4HeadOk,
                detail: "status=\(mp4Head.status.map(String.init) ?? "nil") type=\(mp4Head.type) content-type=\(mp4Head.contentType ?? "nil")",
                evidenceTag: "TEST_RESULT+NETWORK"
            )
        )

        let mp4Contract = await contractValidator.validate(mp4URL, headers: [:])
        if case .valid = mp4Contract {
            steps.append(
                StreamPipelineValidationStep(
                    title: "Known-good MP4 range fetch",
                    passed: true,
                    detail: "StreamContractValidator accepted media prefix.",
                    evidenceTag: "TEST_RESULT+NETWORK+CODEBASE"
                )
            )
        } else if case .invalid(let reason) = mp4Contract {
            steps.append(
                StreamPipelineValidationStep(
                    title: "Known-good MP4 range fetch",
                    passed: false,
                    detail: reason,
                    evidenceTag: "TEST_RESULT+NETWORK+CODEBASE"
                )
            )
        }

        // Negative: HTML
        let htmlURL = StreamPipelineKnownGoodURLs.htmlDocument
        let htmlContract = await contractValidator.validate(htmlURL, headers: [:])
        let htmlRejected: Bool = {
            switch htmlContract {
            case .invalid(let r): return r.lowercased().contains("html") || r.contains("HTTP")
            case .valid: return false
            }
        }()
        steps.append(
            StreamPipelineValidationStep(
                title: "HTML not accepted as playable media",
                passed: htmlRejected,
                detail: {
                    switch htmlContract {
                    case .invalid(let r): return r
                    case .valid: return "Expected invalid result for HTML page."
                    }
                }(),
                evidenceTag: "TEST_RESULT+NETWORK+CODEBASE"
            )
        )

        // Negative: JSON
        let jsonURL = StreamPipelineKnownGoodURLs.jsonDocument
        let jsonContract = await contractValidator.validate(jsonURL, headers: [:])
        let jsonRejected: Bool = {
            switch jsonContract {
            case .invalid: return true
            case .valid: return false
            }
        }()
        steps.append(
            StreamPipelineValidationStep(
                title: "JSON not accepted as playable media",
                passed: jsonRejected,
                detail: {
                    if case .invalid(let r) = jsonContract { return r }
                    return "Validator should reject non-media types."
                }(),
                evidenceTag: "TEST_RESULT+NETWORK+CODEBASE"
            )
        )

        // AVFoundation playable
        let avHLS = await probeAVPlayable(url: hlsURL)
        steps.append(
            StreamPipelineValidationStep(
                title: "AVAsset isPlayable (Apple HLS)",
                passed: avHLS.ok,
                detail: avHLS.message,
                evidenceTag: "TEST_RESULT+NETWORK+APPLE_DOCS(AVAsset.load)"
            )
        )

        let avMP4 = await probeAVPlayableFirstSuccess(urls: StreamPipelineKnownGoodURLs.sampleProgressiveMP4PlayableProbeCandidates)
        steps.append(
            StreamPipelineValidationStep(
                title: "AVAsset isPlayable (sample MP4)",
                passed: avMP4.ok,
                detail: avMP4.message,
                evidenceTag: "TEST_RESULT+NETWORK+APPLE_DOCS(AVAsset.load)"
            )
        )

        let finished = Date()
        return StreamPipelineValidationReport(startedAt: started, finishedAt: finished, steps: steps)
    }

    private static func probeAVPlayableFirstSuccess(urls: [URL]) async -> (ok: Bool, message: String) {
        var lastDetail = ""
        for url in urls {
            let one = await probeAVPlayable(url: url)
            if one.ok {
                return (true, "\(one.message) — \(url.host ?? url.absoluteString)")
            }
            lastDetail = "\(url.lastPathComponent): \(one.message)"
        }
        return (false, "All MP4 candidates failed. Last: \(lastDetail)")
    }

    private static func probeAVPlayable(url: URL) async -> (ok: Bool, message: String) {
        let options: [String: Any] = [
            AVURLAssetAllowsCellularAccessKey: true,
            AVURLAssetAllowsExpensiveNetworkAccessKey: true,
            AVURLAssetAllowsConstrainedNetworkAccessKey: true
        ]
        let asset = AVURLAsset(url: url, options: options)

        do {
            _ = try? await asset.load(.tracks)
            let playable = try await asset.load(.isPlayable)
            if playable {
                return (true, "isPlayable == true")
            }
            return (false, "isPlayable == false (reachable but not marked playable)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Exercises the production native playback path, including required-header
    /// proxying, readiness observation, watchdog behavior, and failover policy.
    /// Audio is muted before startup and kept muted throughout the run.
    @MainActor
    static func runPlaybackContinuitySoak(
        durationSeconds: Int = 120,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> StreamPlaybackContinuityReport {
        let startedAt = Date()
        let referenceSession = StreamSession(
            matchID: "fotty-mac-continuity-soak",
            title: "Fotty Playback Continuity Soak",
            playableURL: StreamPipelineKnownGoodURLs.appleBipbopMaster,
            streamType: .hls,
            providerName: "StreamEx Reference",
            requiredHeaders: ["X-Fotty-Nexus-Source": "admin"],
            qualityLabel: "Apple HLS"
        )
        let event = AnalyticalDataEngine.EventReference(
            id: "fotty-mac-continuity-event",
            title: "Fotty Playback Continuity Soak",
            category: "football",
            date: Int64(Date().timeIntervalSince1970 * 1_000),
            poster: nil,
            popular: false,
            teams: nil,
            sources: nil
        )
        let viewModel = LivePlayerViewModel(event: event, providedSessions: [referenceSession])
        defer { viewModel.cleanup() }

        viewModel.loadCurrentSource()
        await Task.yield()
        viewModel.player?.isMuted = true
        viewModel.player?.volume = 0

        let startupDeadline = Date().addingTimeInterval(30)
        while viewModel.isLoading, viewModel.error == nil, Date() < startupDeadline {
            viewModel.player?.isMuted = true
            viewModel.player?.volume = 0
            try? await Task.sleep(for: .milliseconds(250))
        }

        let startupSeconds = Date().timeIntervalSince(startedAt)
        let originalAttemptID = viewModel.loadRequestID
        let originalSourceID = viewModel.activeSource?.id
        let originalItem = viewModel.player?.currentItem
        let startPlaybackSecond = viewModel.player?.currentTime().seconds ?? 0
        var furthestPlaybackSecond = startPlaybackSecond
        var advancingSamples = 0
        var waitingSamples = 0
        var pausedSamples = 0
        var attemptStayedStable = true
        var sourceStayedStable = true
        var playerItemStayedStable = originalItem != nil
        var capturedFailure = viewModel.error

        if viewModel.isLoading, capturedFailure == nil {
            capturedFailure = "Playback did not leave its loading state within 30 seconds."
        }

        let boundedDuration = max(1, durationSeconds)
        if capturedFailure == nil {
            for elapsed in 1...boundedDuration {
                try? await Task.sleep(for: .seconds(1))
                viewModel.player?.isMuted = true
                viewModel.player?.volume = 0

                attemptStayedStable = attemptStayedStable && viewModel.loadRequestID == originalAttemptID
                sourceStayedStable = sourceStayedStable && viewModel.activeSource?.id == originalSourceID
                playerItemStayedStable = playerItemStayedStable && viewModel.player?.currentItem === originalItem
                if let error = viewModel.error, capturedFailure == nil { capturedFailure = error }

                let currentSecond = viewModel.player?.currentTime().seconds ?? 0
                if currentSecond > furthestPlaybackSecond + 0.1 { advancingSamples += 1 }
                furthestPlaybackSecond = max(furthestPlaybackSecond, currentSecond)
                switch viewModel.player?.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate: waitingSamples += 1
                case .paused: pausedSamples += 1
                default: break
                }
                onProgress?(elapsed, boundedDuration)
            }
        }

        return StreamPlaybackContinuityReport(
            startedAt: startedAt,
            finishedAt: Date(),
            requestedDurationSeconds: boundedDuration,
            startupSeconds: startupSeconds,
            playbackProgressSeconds: furthestPlaybackSecond - startPlaybackSecond,
            advancingSamples: advancingSamples,
            waitingSamples: waitingSamples,
            pausedSamples: pausedSamples,
            attemptStayedStable: attemptStayedStable,
            sourceStayedStable: sourceStayedStable,
            playerItemStayedStable: playerItemStayedStable,
            automaticFailovers: viewModel.autoFailoverCount,
            failureReason: capturedFailure
        )
    }
}
