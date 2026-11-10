import XCTest
@testable import Fotty

/// Player shrink slice 7: the single-player recovery overrides moved from the
/// view model into `LivePlaybackRecoveryPolicy`, pinned to their inline rules.
final class LivePlaybackRecoveryOverridesTests: XCTestCase {
    private typealias Policy = LivePlaybackRecoveryPolicy

    func testHardFailureListsDifferOnlyByLeaseExpiry() {
        XCTAssertEqual(Policy.unrecoverablePreparationReasons,
                       ["unsafe_redirect", "descriptor_fixture_changed", "invalid_match_mapping", "unsafe_response"])
        XCTAssertEqual(Policy.offlineWaitRefusedReasons.subtracting(Policy.unrecoverablePreparationReasons), ["lease_expired"])
    }

    func testOfflineWaitOverride() {
        let wait = Policy.Action.waitForNetwork(.network)
        func override(_ action: Policy.Action, single: Bool = true, status: Int? = nil, prep: String? = nil) -> Policy.Action {
            Policy.overridingOfflineWait(action, isSinglePlayer: single,
                structuredFailure: status.map { LivePlaybackStructuredFailure(httpStatus: $0) },
                preparationReason: prep, reason: "Network unavailable", countsAsStall: false)
        }
        XCTAssertEqual(override(wait), wait, "An ordinary offline failure still waits")
        XCTAssertEqual(override(wait, single: false, prep: "unsafe_redirect"), wait, "Shared players keep waiting")
        if case .exhaustSource = override(wait, prep: "unsafe_redirect") {} else { XCTFail("Hard preparation failure") }
        if case .exhaustSource = override(wait, prep: "lease_expired") {} else { XCTFail("Expired lease cannot be replayed") }
        if case .exhaustSource = override(wait, status: 403) {} else { XCTFail("Typed denial") }
        XCTAssertEqual(override(wait, status: 408), wait, "408 allows an automatic retry")
        let retry = Policy.Action.retryNativeStartup(.network)
        XCTAssertEqual(override(retry, prep: "unsafe_redirect"), retry, "Only a network wait is overridden")
    }

    private func liveWindow() -> Policy.LiveWindowStallInput {
        .init(isSingleRankedPlayer: true, isSessionRetired: false, isUsingWebEmbed: false, isPlaying: true,
              hasDecoded: true, countsAsStall: true,
              nativeFailureTrigger: NativePlaybackDiagnosticTrigger.stallTimeout.rawValue,
              isNetworkReachable: true, isForcedWebEmbed: false, reason: "Playback stalled.",
              structuredFailure: nil, isDirectMedia: true, boundProviderCode: "communitysports",
              hasCatalogIdentityConflict: false, timingAllowsPlayback: true, bindingMatchesEvent: true,
              sessionCanRefresh: true, nativeStartupRetryCount: 0, descriptorRefreshAttempted: false,
              hasCurrentItem: true, preparationReason: nil)
    }

    func testLiveWindowStallRetry() {
        let exhaust = Policy.Action.exhaustSource(.stalled)
        let stalled = Policy.RelayWindow(isNonAdvancing: { true }, isAdvancing: { false })
        let advancing = Policy.RelayWindow(isNonAdvancing: { false }, isAdvancing: { true })
        let quiet = Policy.RelayWindow(isNonAdvancing: { false }, isAdvancing: { false })
        XCTAssertTrue(Policy.retriesLiveWindowStall(after: exhaust, liveWindow(), relay: stalled))
        XCTAssertTrue(Policy.retriesLiveWindowStall(after: exhaust, liveWindow(), relay: advancing))
        XCTAssertFalse(Policy.retriesLiveWindowStall(after: exhaust, liveWindow(), relay: quiet))
        XCTAssertFalse(Policy.retriesLiveWindowStall(after: exhaust, liveWindow(), relay: nil), "No relay")
        XCTAssertFalse(Policy.retriesLiveWindowStall(after: .retryNativeStartup(.stalled), liveWindow(), relay: stalled),
                       "Only an exhausted source is reconsidered")

        var prepared = liveWindow(); prepared.preparationReason = "transport_error"
        XCTAssertTrue(Policy.retriesLiveWindowStall(after: exhaust, prepared, relay: stalled))
        XCTAssertFalse(Policy.retriesLiveWindowStall(after: exhaust, prepared, relay: advancing),
                       "A preparation failure never earns advancing-window recovery")

        for provider in ["communitysports", "plaviosports", "reviewedtv"] {
            var input = liveWindow(); input.boundProviderCode = provider
            XCTAssertTrue(Policy.retriesLiveWindowStall(after: exhaust, input, relay: stalled), provider)
        }
        let blockers: [(String, (inout Policy.LiveWindowStallInput) -> Void)] = [
            ("multi", { $0.isSingleRankedPlayer = false }), ("retired", { $0.isSessionRetired = true }),
            ("web", { $0.isUsingWebEmbed = true }), ("paused", { $0.isPlaying = false }),
            ("undecoded", { $0.hasDecoded = false }), ("not a stall", { $0.countsAsStall = false }),
            ("other trigger", { $0.nativeFailureTrigger = "item_status_failed" }),
            ("offline", { $0.isNetworkReachable = false }), ("forced web", { $0.isForcedWebEmbed = true }),
            ("denial", { $0.structuredFailure = LivePlaybackStructuredFailure(httpStatus: 403) }),
            ("not direct media", { $0.isDirectMedia = false }), ("unbound", { $0.boundProviderCode = nil }),
            ("other provider", { $0.boundProviderCode = "score808" }),
            ("identity conflict", { $0.hasCatalogIdentityConflict = true }),
            ("timing", { $0.timingAllowsPlayback = false }), ("binding", { $0.bindingMatchesEvent = false }),
            ("cannot refresh", { $0.sessionCanRefresh = false }), ("retry spent", { $0.nativeStartupRetryCount = 1 }),
            ("renewal tried", { $0.descriptorRefreshAttempted = true }), ("no item", { $0.hasCurrentItem = false }),
        ]
        for (name, block) in blockers {
            var input = liveWindow(); block(&input)
            XCTAssertFalse(Policy.retriesLiveWindowStall(after: exhaust, input, relay: stalled), name)
        }
    }

    func testRelayWindowIsReadLastAndInOrder() {
        var reads: [String] = []
        let relay = Policy.RelayWindow(isNonAdvancing: { reads.append("non"); return true },
                                       isAdvancing: { reads.append("adv"); return true })
        var blocked = liveWindow(); blocked.isPlaying = false
        XCTAssertFalse(Policy.retriesLiveWindowStall(after: .exhaustSource(.stalled), blocked, relay: relay))
        XCTAssertEqual(reads, [], "The relay is not read when another condition fails")
        XCTAssertTrue(Policy.retriesLiveWindowStall(after: .exhaustSource(.stalled), liveWindow(), relay: relay))
        XCTAssertEqual(reads, ["non"], "Advancing is read only when the window is not stalled")
    }

    func testFreshDeliveryRule() {
        func can(_ kind: LivePlaybackFailureKind, status: Int? = nil, category: LivePlaybackStructuredFailure.Category? = nil,
                 details: [String: String] = [:], decoded: Bool = false, channel: Bool = false, online: Bool = true) -> Bool {
            let failure = status != nil || category != nil ? LivePlaybackStructuredFailure(httpStatus: status, category: category) : nil
            return Policy.canAwaitFreshDelivery(failureKind: kind, structuredFailure: failure, diagnosticDetails: details,
                hasDecodedDuringSession: decoded, isBroadcastChannel: channel, isNetworkReachable: online)
        }
        for reason in Policy.unrecoverablePreparationReasons {
            XCTAssertFalse(can(.sourceFailure, status: 503, details: ["preparation_reason": reason], decoded: true), reason)
        }
        XCTAssertTrue(can(.sourceFailure, status: 503))
        XCTAssertTrue(can(.sourceFailure, decoded: true), "Jet, 8 Nov: a decoded session gets one fresh lookup")
        XCTAssertFalse(can(.sourceFailure, decoded: true, channel: true))
        XCTAssertFalse(can(.accessDenied, decoded: true))
        XCTAssertTrue(can(.sourceFailure, details: ["preparation_reason": "lease_expired"]))
        XCTAssertTrue(can(.startupTimeout, details: ["native_failure_trigger": NativePlaybackDiagnosticTrigger.readinessTimeout.rawValue]))
        XCTAssertFalse(can(.startupTimeout))
        XCTAssertFalse(can(.sourceFailure))
    }
}
