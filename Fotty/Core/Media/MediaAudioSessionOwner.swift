import AVFoundation
import Foundation
import UIKit
import os

struct MediaAudioSessionFailure: Equatable, Sendable {
    enum Stage: String, Sendable { case configuration, activation }
    let stage: Stage
    let code: Int
}

enum MediaAudioSessionPreparation: Equatable, Sendable {
    case completed([MediaAudioSessionFailure])
    case cancelled

    var mayContinue: Bool {
        if case .completed = self { return true }
        return false
    }
}

protocol MediaAudioSessionBackend: Sendable {
    func configure() async throws
    func activate() async throws
}

struct MediaAudioPlaybackIdentity: Equatable {
    let requestID: UUID
    let sourceID: UUID?
    let intentID: UUID
    let playerID: ObjectIdentifier?
    let itemID: ObjectIdentifier?

    init(requestID: UUID, sourceID: UUID?, intentID: UUID, player: AVPlayer?, item: AVPlayerItem?) {
        self.requestID = requestID
        self.sourceID = sourceID
        self.intentID = intentID
        self.playerID = player.map(ObjectIdentifier.init)
        self.itemID = item.map(ObjectIdentifier.init)
    }
}

@MainActor
enum MediaAudioPlaybackGate {
    /// The platform can finish activation after Pause, replacement or dismissal.
    /// Preparation completion alone never grants permission to play.
    static func prepare(using preparation: @MainActor () async -> MediaAudioSessionPreparation,
                        isCurrent: () -> Bool) async -> Bool {
        guard !Task.isCancelled, isCurrent() else { return false }
        let result = await preparation()
        return result.mayContinue && !Task.isCancelled && isCurrent()
    }

    static func prepareNative(using preparation: @MainActor () async -> MediaAudioSessionPreparation,
                              expected: MediaAudioPlaybackIdentity,
                              currentIdentity: () -> MediaAudioPlaybackIdentity,
                              playbackMayStart: () -> Bool) async -> Bool {
        await prepare(using: preparation, isCurrent: {
            expected == currentIdentity() && playbackMayStart()
        })
    }
}

/// AVAudioSession calls are confined to this serial queue. Even the legacy
/// blocking activation must never run on the UI actor. SDK 27's asynchronous
/// activation keeps the same completion ordering without blocking this queue.
final class SystemMediaAudioSessionBackend: MediaAudioSessionBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jelani.Fotty.audio-session", qos: .userInitiated)

    func configure() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    // Playback already supports AirPlay/A2DP. The older route
                    // options caused error -50 on some supported iPads.
                    if session.category != .playback || session.mode != .moviePlayback || !session.categoryOptions.isEmpty {
                        try session.setCategory(.playback, mode: .moviePlayback, options: [])
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func activate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                if #available(iOS 27.0, *) {
                    session.activate(options: []) { activated, error in
                        if let error { continuation.resume(throwing: error) }
                        else if activated { continuation.resume() }
                        else { continuation.resume(throwing: NSError(domain: "FottyAudioSession", code: -1)) }
                    }
                } else {
                    do { try session.setActive(true); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}

/// Only platform preparation is shared here. Playback intent, AVPlayer,
/// WebKit/PiP and source attempts remain owned by their existing native owners.
actor MediaAudioSessionOwner {
    struct ActivationDiagnostic: Sendable {
        let jobID: UUID
        let phase: FottyPlaybackDiagnosticPhase
        let result: FottyPlaybackDiagnosticResult

        func record(in store: FottyQualityStore = .shared) {
            store.record(category: .playback, name: "audio_activation_evidence", outcome: .info, details: [
                "audio_job_id": jobID.uuidString,
                "diagnostic_phase": phase.rawValue,
                "diagnostic_purpose": FottyPlaybackDiagnosticPurpose.platformActivation.rawValue,
                "diagnostic_result": result.rawValue
            ])
        }
    }
    private struct Waiter {
        let activates: Bool
        let continuation: CheckedContinuation<MediaAudioSessionPreparation, Never>
    }
    private struct Job {
        let id: UUID
        let epoch: UUID
        var waiters: [UUID: Waiter]
        var activates: Bool { waiters.values.contains { $0.activates } }
    }

    private let backend: any MediaAudioSessionBackend
    private let diagnostic: @Sendable (ActivationDiagnostic) -> Void
    // No timer or unbounded job history. Normal audio continues after the local
    // evidence cap; diagnostics must never control platform preparation.
    private var diagnosedActivationCount = 0
    static let maximumDiagnosedActivations = 64
    private var epoch = UUID()
    private var active: Job?
    private var pending: [Job] = []

    init(backend: any MediaAudioSessionBackend,
         diagnostic: @escaping @Sendable (ActivationDiagnostic) -> Void = { _ in }) {
        self.backend = backend
        self.diagnostic = diagnostic
    }

    /// Introspection for deterministic request-barrier tests, not playback
    /// state or permission to start any player.
    var pendingRequestCount: Int {
        (active?.waiters.count ?? 0) + pending.reduce(0) { $0 + $1.waiters.count }
    }

    func prepare(activate: Bool = false) async -> MediaAudioSessionPreparation {
        let waiter = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: .cancelled); return }
                enqueue(waiter, activates: activate, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(waiter) }
        }
    }

    func resetAndConfigure() async -> MediaAudioSessionPreparation {
        epoch = UUID()
        return await prepare()
    }

    private func enqueue(_ waiter: UUID, activates: Bool,
                         continuation: CheckedContinuation<MediaAudioSessionPreparation, Never>) {
        if var job = active, job.epoch == epoch {
            job.waiters[waiter] = Waiter(activates: activates, continuation: continuation)
            active = job
        } else if let index = pending.firstIndex(where: { $0.epoch == epoch }) {
            pending[index].waiters[waiter] = Waiter(activates: activates, continuation: continuation)
        } else {
            pending.append(Job(id: UUID(), epoch: epoch, waiters: [waiter: Waiter(activates: activates, continuation: continuation)]))
        }
        startNext()
    }

    private func cancel(_ waiter: UUID) {
        if let cancelled = active?.waiters.removeValue(forKey: waiter) {
            cancelled.continuation.resume(returning: .cancelled)
            return
        }
        for index in pending.indices {
            if let cancelled = pending[index].waiters.removeValue(forKey: waiter) {
                cancelled.continuation.resume(returning: .cancelled)
                pending.removeAll { $0.waiters.isEmpty }
                return
            }
        }
    }

    private func startNext() {
        guard active == nil, !pending.isEmpty else { return }
        active = pending.removeFirst()
        let id = active!.id
        Task { await run(id) }
    }

    private func run(_ id: UUID) async {
        var failures: [MediaAudioSessionFailure] = []
        do { try await backend.configure() }
        catch { failures.append(.init(stage: .configuration, code: (error as NSError).code)) }
        guard let job = active, job.id == id else { return }
        // A services reset invalidates preparation, never playback intent.
        // Requeue surviving waiters rather than authorizing an old completion.
        if job.epoch == epoch, job.activates, !job.waiters.isEmpty {
            let recordsActivation = diagnosedActivationCount < Self.maximumDiagnosedActivations
            if recordsActivation {
                diagnosedActivationCount += 1
                diagnostic(.init(jobID: id, phase: .audioActivationRequested, result: .began))
            }
            var activationResult = FottyPlaybackDiagnosticResult.completed
            do { try await backend.activate() }
            catch {
                activationResult = .completedWithErrors
                failures.append(.init(stage: .activation, code: (error as NSError).code))
            }
            if recordsActivation {
                diagnostic(.init(jobID: id, phase: .audioActivationFinished, result: activationResult))
            }
        }
        finish(id, failures: failures)
    }

    private func finish(_ id: UUID, failures: [MediaAudioSessionFailure]) {
        guard let job = active, job.id == id else { return }
        active = nil
        if job.epoch != epoch, !job.waiters.isEmpty {
            if let index = pending.firstIndex(where: { $0.epoch == epoch }) {
                pending[index].waiters.merge(job.waiters) { first, _ in first }
            } else {
                pending.insert(Job(id: UUID(), epoch: epoch, waiters: job.waiters), at: 0)
            }
        } else {
            for waiter in job.waiters.values { waiter.continuation.resume(returning: .completed(failures)) }
        }
        startNext()
    }
}

/// One local facade; configuration demand does not activate the session at
/// launch, navigation or two-match audio-focus changes.
@MainActor
enum MediaAudioSession {
    private static let owner = MediaAudioSessionOwner(backend: SystemMediaAudioSessionBackend(),
                                                     diagnostic: { $0.record() })
    private static let logger = Logger(subsystem: "com.jelani.Fotty", category: "AudioSession")
    private static var observerTokens: [NSObjectProtocol] = []

    static func configureForPlaybackIfNeeded() {
        Task { _ = await configureForPlayback() }
    }

    static func configureForPlayback() async -> MediaAudioSessionPreparation {
        report(await owner.prepare())
    }

    static func activateForPlaybackIfNeeded() async -> MediaAudioSessionPreparation {
        report(await owner.prepare(activate: true))
    }

    private static func report(_ result: MediaAudioSessionPreparation) -> MediaAudioSessionPreparation {
        if case .completed(let failures) = result {
            for failure in failures {
                logger.error("audio_stage=\(failure.stage.rawValue, privacy: .public) code=\(failure.code, privacy: .public)")
                FottyQualityStore.shared.record(category: .playback, name: "audio_session_preparation",
                    outcome: .failure, details: ["stage": failure.stage.rawValue, "platform_error_code": String(failure.code)])
            }
        }
        return result
    }

    static func configureNativeBackgroundPlayback(_ player: AVPlayer) {
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    static func configureNativeLivePlaybackItem(_ item: AVPlayerItem) {
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    }

    static func installLifecycleObserversIfNeeded() {
        guard observerTokens.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.interruptionNotification] {
            observerTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { notification in
                if name == AVAudioSession.interruptionNotification {
                    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                }
                Task { @MainActor in configureForPlaybackIfNeeded() }
            })
        }
        observerTokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main) { _ in
                Task { @MainActor in _ = report(await owner.resetAndConfigure()) }
            })
    }
}
