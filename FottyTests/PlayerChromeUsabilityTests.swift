import XCTest
import SwiftUI
import UIKit
@testable import Fotty

final class PlayerChromeUsabilityTests: XCTestCase {
    @MainActor
    func testLoadingCandidatesKeepIntrinsicHeightForLongPhase() {
        let content = PlaybackLoadingContent(phase: "Connecting…", category: "cricket")
        let longContent = PlaybackLoadingContent(
            phase: "Waiting for the broadcast to reconnect. Checking the current source without changing your match.",
            category: "cricket")
        let width = 288.0
        let proposal = CGSize(width: width, height: 2_000)

        let full = UIHostingController(rootView: content.fullPresentation
            .environment(\.dynamicTypeSize, .large).frame(width: width))
        let compact = UIHostingController(rootView: content.compactPresentation
            .environment(\.dynamicTypeSize, .large).frame(width: width))
        let longText = UIHostingController(rootView: longContent.fullPresentation
            .environment(\.dynamicTypeSize, .accessibility5).frame(width: width))
        longText.loadViewIfNeeded()
        longText.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        longText.view.frame = CGRect(origin: .zero, size: proposal)
        longText.view.layoutIfNeeded()

        let fullSize = full.sizeThatFits(in: proposal)
        let compactSize = compact.sizeThatFits(in: proposal)
        let longTextSize = longText.sizeThatFits(in: proposal)
        XCTAssertEqual(fullSize.width, width, accuracy: 1)
        XCTAssertEqual(compactSize.width, width, accuracy: 1)
        XCTAssertGreaterThan(fullSize.height, compactSize.height,
                             "The compact candidate must actually release vertical space")
        // A short phase can correctly fit the full presentation. Off-screen
        // Catalyst also need not expand semantic fonts from accessibility traits.
        // This long-phase fixture verifies actual wrapping/intrinsic overflow,
        // not an assumed font size or physical-device accessibility acceptance.
        XCTAssertGreaterThan(longTextSize.height, 162,
                             "A genuinely taller phase must keep its intrinsic height so ViewThatFits rejects it")
    }

    @MainActor
    func testLoadingContentStaysBoundedForNarrowAndShortPlayerSurfaces() {
        let phase = "Waiting for the broadcast to reconnect. Checking the current source without changing your match."
        for (size, type) in [(CGSize(width: 288, height: 162), DynamicTypeSize.large),
                             (CGSize(width: 343, height: 193), .accessibility5),
                             (CGSize(width: 640, height: 120), .accessibility5)] {
            let host = UIHostingController(rootView:
                PlaybackLoadingContent(phase: phase, category: "football", competition: .championsLeague)
                    .environment(\.dynamicTypeSize, type)
                    .frame(width: size.width, height: size.height))
            if type.isAccessibilitySize {
                host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            }
            let measured = host.sizeThatFits(in: size)
            XCTAssertEqual(measured.width, size.width, accuracy: 1)
            XCTAssertEqual(measured.height, size.height, accuracy: 1)
        }
    }

    func testViewingStatusDescribesRecoveryInsteadOfTransportIntent() {
        for mode in [LivePlaybackMode.native, .webEmbed] {
            XCTAssertTrue(LivePlaybackState.recovering(mode).isPlaying,
                          "Keep the existing recovery ownership semantics")
            XCTAssertEqual(ViewingPlaybackCopy.status(state: .recovering(mode), hasError: false,
                userWantsPlayback: true, isNetworkReachable: true), "Reconnecting…")
            XCTAssertEqual(ViewingPlaybackCopy.status(state: .recovering(mode), hasError: false,
                userWantsPlayback: true, isNetworkReachable: false), "Waiting for connection…")
            XCTAssertEqual(ViewingPlaybackCopy.status(state: .connecting(mode), hasError: false,
                userWantsPlayback: true, isNetworkReachable: true), "Connecting…")
            XCTAssertEqual(ViewingPlaybackCopy.status(state: .playing(mode), hasError: false,
                userWantsPlayback: true, isNetworkReachable: true), "Playing")
            XCTAssertEqual(ViewingPlaybackCopy.status(state: .paused(mode), hasError: false,
                userWantsPlayback: true, isNetworkReachable: true), "Paused")
            XCTAssertEqual(ViewingPlaybackCopy.status(state: .recovering(mode), hasError: false,
                userWantsPlayback: false, isNetworkReachable: false), "Paused")
        }
        XCTAssertEqual(ViewingPlaybackCopy.status(state: .failed, hasError: false,
            userWantsPlayback: true, isNetworkReachable: true), "Source unavailable")
        XCTAssertEqual(ViewingPlaybackCopy.status(state: .playing(.native), hasError: true,
            userWantsPlayback: true, isNetworkReachable: true), "Source unavailable")
        XCTAssertEqual(ViewingPlaybackCopy.status(state: .idle, hasError: false,
            userWantsPlayback: true, isNetworkReachable: true), "Ready")
        XCTAssertEqual(ViewingPlaybackCopy.status(state: .preparingNativeHandoff, hasError: false,
            userWantsPlayback: true, isNetworkReachable: true), "Playing")
    }

    @MainActor
    func testCompactRecoveryKeepsAlternateSourcesWithoutInventingAnAlternative() {
        let match = event(title: "Trinbago Knight Riders vs Saint Lucia Kings")
        for count in 0...3 {
            let sessions = (0..<count).map { index in
                StreamSession(matchID: match.id,
                    playableURL: URL(string: "https://example.invalid/source-\(index).m3u8")!,
                    streamType: .hls, providerName: "Score808")
            }
            let model = LivePlayerViewModel(event: match, providedSessions: sessions, ownsRemoteCommands: false)
            defer { model.cleanup() }
            let attempt = model.loadRequestID
            for compact in [true, false] {
                let recovery = PlaybackErrorOverlay(title: "Unavailable", message: "Try another source.",
                    viewModel: model, sourceRecoveryButtonTitle: "Choose another source", dismiss: {},
                    isCompact: compact, onRetry: {}, onShowBroadcastSources: {})
                XCTAssertEqual(recovery.offersAlternateSource, count > 1)
            }
            XCTAssertEqual(model.loadRequestID, attempt)
            XCTAssertNil(model.player, "Presentation must not start or replace transport")
        }
    }

    func testFocusRequiresAnActuallyWideLandscapeWindow() {
        XCTAssertTrue(MultiLiveLayoutPolicy.canFocus(in: CGSize(width: 1180, height: 820)))
        XCTAssertTrue(MultiLiveLayoutPolicy.canFocus(in: CGSize(width: 900, height: 600)))
        for size in [CGSize(width: 899, height: 600), CGSize(width: 900, height: 900),
                     CGSize(width: 820, height: 1180), CGSize(width: 393, height: 852)] {
            XCTAssertFalse(MultiLiveLayoutPolicy.canFocus(in: size), "No enlargement in \(size)")
        }
    }

    func testRecoveryUsesTheBoundedRemainingPaneInsteadOfTheFittedVideoWidth() {
        let pane = CGSize(width: 820, height: 250)
        let chrome = MultiLivePanelChromeLayout.inline.reservedHeight(controlHeight: 44)
        let video = MultiLiveLayoutPolicy.surfaceSize(in: pane, chromeHeight: chrome, isRecovering: false)
        let recovery = MultiLiveLayoutPolicy.surfaceSize(in: pane, chromeHeight: chrome, isRecovering: true)
        XCTAssertEqual(video.height, 193)
        XCTAssertEqual(video.width / video.height, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(recovery, CGSize(width: 820, height: 193))
        XCTAssertLessThan(video.width, recovery.width)
        XCTAssertEqual(recovery.height + chrome, pane.height)
    }

    func testAccessibilityRecoveryReservesScaledControlsAndNeverOverflowsAPane() {
        let pane = CGSize(width: 352, height: 450)
        let chrome = MultiLivePanelChromeLayout.accessibility.reservedHeight(controlHeight: 88)
        let recovery = MultiLiveLayoutPolicy.surfaceSize(in: pane, chromeHeight: chrome, isRecovering: true)
        XCTAssertEqual(recovery, CGSize(width: 352, height: 161))
        XCTAssertEqual(MultiLiveLayoutPolicy.surfaceSize(in: CGSize(width: 352, height: 200),
            chromeHeight: chrome, isRecovering: true).height, 0)
    }

    func testOneSourceRecoveryIsDirectRatherThanAnotherChoiceMenu() {
        XCTAssertEqual(MultiLiveRecoveryAction.action(sourceCount: 0), .none)
        XCTAssertEqual(MultiLiveRecoveryAction.action(sourceCount: 1), .retry)
        for count in [2, 6, 20] {
            XCTAssertEqual(MultiLiveRecoveryAction.action(sourceCount: count), .chooseSource)
        }
    }

    @MainActor
    func testPortraitIdentityDoesNotInventTeamsForChannelsOrSingleEvents() {
        for title in ["Willow Cricket", "Fox Cricket", "Cricket highlights", "Golf championship"] {
            let identity = PlayerPortraitIdentity(event: event(title: title), status: "Broadcast")
            XCTAssertFalse(identity.hasTeamPair, title)
        }
        XCTAssertFalse(PlayerPortraitIdentity(event: event(title: "Home vs Away"), status: "Broadcast").hasTeamPair)
        XCTAssertTrue(PlayerPortraitIdentity(event: event(title: "Trinbago Knight Riders vs Saint Lucia Kings"),
            status: "Live broadcast").hasTeamPair)
    }

    @MainActor
    func testPortraitTeamIdentityWrapsLongNamesAtPhoneWidths() {
        let short = PlayerPortraitIdentity(event: event(title: "A vs B"), status: "Live broadcast")
        let long = PlayerPortraitIdentity(event: event(title:
            "Brighton and Hove Albion Under 19 vs Wolverhampton Wanderers Under 19"), status: "Live broadcast")
        for width in [180.0, 240.0] {
            let proposal = CGSize(width: width, height: 2000)
            let shortSize = UIHostingController(rootView: short.frame(width: width)).sizeThatFits(in: proposal)
            let longSize = UIHostingController(rootView: long.frame(width: width)).sizeThatFits(in: proposal)
            XCTAssertEqual(longSize.width, width, accuracy: 1)
            XCTAssertTrue(longSize.height.isFinite)
            XCTAssertGreaterThan(longSize.height, shortSize.height, "Long names must wrap, not shrink: \(width)")
        }
    }

    func testLiveOrPastKickoffLineupCopyDoesNotPromisePreMatchConfirmation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for status in [FottyMatchStatus.live, .halfTime, .extraTime, .penalties, .postponed, .cancelled, .unknown] {
            let copy = MatchHubLineupAvailabilityCopy.presentation(status: status,
                kickoff: now.addingTimeInterval(3600), at: now)
            XCTAssertEqual(copy.title, "Lineups unavailable")
            XCTAssertNil(copy.message, "\(status) must not promise upcoming lineups")
        }
        for status in [FottyMatchStatus.scheduled, .preMatch] {
            XCTAssertNil(MatchHubLineupAvailabilityCopy.presentation(status: status, kickoff: now, at: now).message)
            XCTAssertNil(MatchHubLineupAvailabilityCopy.presentation(status: status,
                kickoff: now.addingTimeInterval(-60), at: now).message)
            XCTAssertEqual(MatchHubLineupAvailabilityCopy.presentation(status: status,
                kickoff: now.addingTimeInterval(3600), at: now).message,
                "Confirmed teams usually appear close to kickoff.")
        }
    }

    @MainActor
    private func event(title: String) -> EventReference {
        EventReference(id: "chrome-test", title: title, category: "cricket", date: nil,
            poster: nil, popular: nil, teams: nil, sources: nil)
    }
}
