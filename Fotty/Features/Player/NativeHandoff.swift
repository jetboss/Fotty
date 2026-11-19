import AVFoundation

// Web-to-native handoff support types (player shrink slice 6, 9 Nov 2026).
// `NativeHandoffCandidateDiagnostic` moved here unchanged from
// `LivePlayerViewModel.swift`; the orchestration that uses it stays in the view
// model (see docs/PLAYER-SHRINK-PLAN.md). Watch Two's preflight types were
// removed with Watch Two on 19 Nov 2026.

/// Composition only: callers capture the exact candidate item and relay before
/// retiring them. No active-player lookup, playback decision or invented cause.
enum NativeHandoffCandidateDiagnostic {
    static func details(itemStatus: AVPlayerItem.Status,
                        native: PlayerDiagnosticService.DiagnosticSnapshot,
                        candidateRelayDetails: [String: String]) -> [String: String] {
        var details = native.qualityDetails.merging(candidateRelayDetails) { _, value in value }
        details["native_item_status"] = itemStatusLabel(itemStatus)
        return details
    }

    /// The `native_item_status` receipt value.
    static func itemStatusLabel(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        @unknown default: return "other"
        }
    }
}

/// Native candidates already tried for web-to-native handoff in this player.
/// Each source and URL pair is tried once, and at most 12 in all, so passive
/// discovery cannot loop on a bad candidate. An explicit transfer request may
/// clear one entry to validate it again.
struct NativeHandoffCandidateLedger: Equatable {
    static let maximumAttempts = 12
    private(set) var attempted: Set<String> = []

    var isEmpty: Bool { attempted.isEmpty }

    static func key(sourceID: UUID, url: URL) -> String { "\(sourceID.uuidString)|\(url.absoluteString)" }

    /// Records the attempt and returns true if this candidate may be tried now.
    mutating func admit(sourceID: UUID, url: URL) -> Bool {
        guard attempted.count < Self.maximumAttempts else { return false }
        return attempted.insert(Self.key(sourceID: sourceID, url: url)).inserted
    }

    /// Lets one candidate be validated again after an explicit request.
    mutating func allowRetry(sourceID: UUID, url: URL) {
        attempted.remove(Self.key(sourceID: sourceID, url: url))
    }

    mutating func reset() { attempted.removeAll() }
}
