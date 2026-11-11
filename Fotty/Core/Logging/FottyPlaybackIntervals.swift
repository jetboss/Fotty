import Foundation

enum FottyPlaybackIntervalCompletion: String {
    case decodedProgress = "decoded_progress"
    case transportPlaying = "transport_playing"
    case interrupted, failed, completed, cancelled
    case completedWithErrors = "completed_with_errors"

    var outcome: FottyQualityOutcome {
        switch self {
        case .decodedProgress: .recovered
        case .failed, .completedWithErrors: .failure
        case .transportPlaying, .interrupted, .completed, .cancelled: .info
        }
    }
}

struct FottyPlaybackIntervalRecord {
    let name: String
    let completion: FottyPlaybackIntervalCompletion
    let durationMilliseconds: Int
    let details: [String: String]

    func record(in store: FottyQualityStore = .shared) {
        store.record(category: .playback, name: name, outcome: completion.outcome,
                     durationMilliseconds: durationMilliseconds,
                     details: details.merging(["reason_code": completion.rawValue]) { _, value in value })
    }
}

/// Passive, attempt-bound elapsed evidence. It owns no timer, media, control,
/// observer or network request. First-start buffering is not a playback stall.
/// An interruption is not decoded recovery; missing evidence stays missing.
@MainActor
final class FottyPlaybackIntervals {
    struct Identity: Equatable {
        let sourceID: UUID
        let attemptID: UUID
    }
    private(set) var identity: Identity?
    private(set) var hasDecoded = false
    private(set) var hasDecodedDuringSession = false
    private var context: [String: String] = [:]
    private var stallStartedAt: TimeInterval?
    private var stallContext: [String: String] = [:]
    private(set) var emittedCount = 0
    static let maximumRecordsPerAttempt = 16

    @discardableResult
    func beginAttempt(_ identity: Identity, context: [String: String], now: TimeInterval) -> FottyPlaybackIntervalRecord? {
        if self.identity == identity { self.context = context; return nil }
        let interrupted = finishStall(self.identity, now: now, completion: .interrupted)
        self.identity = identity
        self.context = context
        hasDecoded = false
        stallStartedAt = nil
        stallContext = [:]
        emittedCount = 0
        return interrupted
    }

    func beginStall(_ identity: Identity, now: TimeInterval) {
        guard self.identity == identity, hasDecoded, now.isFinite,
              emittedCount < Self.maximumRecordsPerAttempt, stallStartedAt == nil else { return }
        stallStartedAt = now
        stallContext = context
    }

    @discardableResult
    func decodedProgress(_ identity: Identity, now: TimeInterval) -> FottyPlaybackIntervalRecord? {
        guard self.identity == identity else { return nil }
        hasDecoded = true
        hasDecodedDuringSession = true
        return finishStall(identity, now: now, completion: .decodedProgress)
    }

    @discardableResult
    func finishStall(_ identity: Identity?, now: TimeInterval,
                     completion: FottyPlaybackIntervalCompletion) -> FottyPlaybackIntervalRecord? {
        guard let identity, self.identity == identity, let start = stallStartedAt else { return nil }
        let details = stallContext
        stallStartedAt = nil
        stallContext = [:]
        return makeRecord(name: "stall_observed_duration", start: start, end: now, completion: completion, details: details)
    }

    /// Covers the caller's entire preparation wait, including coalescing and
    /// configuration. It is deliberately not called AVAudioSession activation.
    func audioPreparation(_ identity: Identity, startedAt: TimeInterval, now: TimeInterval,
                          result: MediaAudioSessionPreparation) -> FottyPlaybackIntervalRecord? {
        guard self.identity == identity else { return nil }
        let completion: FottyPlaybackIntervalCompletion
        switch result {
        case .cancelled: completion = .cancelled
        case .completed(let failures): completion = failures.isEmpty ? .completed : .completedWithErrors
        }
        return makeRecord(name: "audio_preparation_duration", start: startedAt, end: now, completion: completion, details: context)
    }

    func audioPreparation(_ identity: Identity, durationMilliseconds: Int,
                          result: MediaAudioSessionPreparation) -> FottyPlaybackIntervalRecord? {
        guard durationMilliseconds >= 0 else { return nil }
        return audioPreparation(identity, startedAt: 0, now: Double(durationMilliseconds) / 1_000, result: result)
    }

    private func makeRecord(name: String, start: TimeInterval, end: TimeInterval,
                            completion: FottyPlaybackIntervalCompletion, details: [String: String]) -> FottyPlaybackIntervalRecord? {
        guard emittedCount < Self.maximumRecordsPerAttempt,
              let duration = Self.elapsedMilliseconds(from: start, to: end) else { return nil }
        emittedCount += 1
        return .init(name: name, completion: completion, durationMilliseconds: duration, details: details)
    }

    nonisolated static func elapsedMilliseconds(from start: TimeInterval, to end: TimeInterval) -> Int? {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        return Int(min((end - start) * 1_000, 3_600_000).rounded(.down))
    }
}
