import AVFoundation

// Web-to-native handoff and Watch Two support types (player shrink slice 6,
// 9 Nov 2026). The two enums and `NativeHandoffCandidateDiagnostic` moved here
// unchanged from `LivePlayerViewModel.swift`. The orchestration that uses them
// stays in the view model: the transfer and Watch Two paths use 68 to 76 of
// its members each, about half of them private, so they are not a clean
// controller seam (see docs/PLAYER-SHRINK-PLAN.md).

enum NativeWatchTwoPreflightStage: String {
    case admission, proxy, validation, isolation, readiness, registration
}

enum NativeWatchTwoPreflightOutcome: String {
    case notEligible = "not_eligible", unsupported = "unsupported", noCandidate = "no_candidate"
    case staleCandidate = "stale_candidate", staleOwner = "stale_owner", cancelled
    case proxyFailed = "proxy_failed", validationRejected = "validation_rejected"
    case isolationFailed = "isolation_failed", readinessFailed = "readiness_failed"
    case readinessTimeout = "readiness_timeout", registrationRejected = "registration_rejected", prepared

    /// Receipt outcome for a preflight: a retained candidate succeeded; losing
    /// ownership or cancellation is informational; anything else failed.
    func qualityOutcome(retained: Bool) -> FottyQualityOutcome {
        if retained { return .success }
        return self == .cancelled || self == .staleOwner ? .info : .failure
    }
}

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
