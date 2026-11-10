import XCTest
import SwiftUI
import UIKit
@testable import Fotty

/// Presentation fixtures only. These do not create a playback model, request a
/// stream or establish physical iPhone/iPad visual or interaction acceptance.
@MainActor
final class Fotty25PlayerDesignTests: XCTestCase {
    func testSingleMatchIdentityWrapsLongNamesWithoutShrinkingOrChangingScore() {
        let short = identity(title: "Arsenal vs Everton")
        let long = identity(title: "Brighton and Hove Albion Under 19 vs Wolverhampton Wanderers Under 19")
        for width in [288.0, 343.0, 720.0] {
            let proposal = CGSize(width: width, height: 2_000)
            let shortSize = UIHostingController(rootView: short.frame(width: width)).sizeThatFits(in: proposal)
            let longSize = UIHostingController(rootView: long.frame(width: width)).sizeThatFits(in: proposal)
            XCTAssertEqual(longSize.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(longSize.height, shortSize.height)
            XCTAssertGreaterThan(longSize.height, 32)
        }
    }

    func testSingleIdentityAndJoinedChoicesRemainBoundedAtAccessibilitySizes() throws {
        let session = StreamSession(matchID: "ui-only", playableURL: URL(string: "https://example.invalid/ui-only.m3u8")!,
                                    streamType: .hls, providerName: "AS1")
        for width in [288.0, 393.0, 640.0] {
            let content = VStack(alignment: .leading, spacing: 16) {
                identity(title: "Zimbabwe Women vs West Indies Women")
                SessionRow(session: session, displayNumber: 1, isActive: true, isFailed: false,
                           currentMode: .native, usesJoinedPresentation: true, action: {})
                SessionRow(session: session, displayNumber: 2, isActive: false, isFailed: true,
                           usesJoinedPresentation: true, action: {})
            }
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            let host = UIHostingController(rootView: content)
            host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            let size = host.sizeThatFits(in: CGSize(width: width, height: 4_000))
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThan(size.height, 2 * 44)
            XCTAssertLessThan(size.height, 4_000)
        }
    }

    func testJoinedSourceSelectionIsVisibleWithoutFillingEveryOptionWithAccent() throws {
        let session = StreamSession(matchID: "ui-only", playableURL: URL(string: "https://example.invalid/ui-only.m3u8")!,
                                    streamType: .hls, providerName: "CS2")
        func image(selected: Bool) throws -> UIImage {
            let renderer = ImageRenderer(content:
                SessionRow(session: session, displayNumber: 2, isActive: selected, isFailed: false,
                           usesJoinedPresentation: true, action: {})
                .frame(width: 343).environment(\.colorScheme, .dark))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }
        let selected = try image(selected: true)
        let other = try image(selected: false)
        XCTAssertEqual(selected.size.width, other.size.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(selected.size.height, 44)
        XCTAssertNotEqual(try XCTUnwrap(selected.pngData()), try XCTUnwrap(other.pngData()))
    }

    func testFocusedPhoneNavigationReflowsInsteadOfSqueezingFourControlsAndLongIdentity() {
        for (width, type) in [(288.0, DynamicTypeSize.large), (343.0, .accessibility5), (640.0, .large)] {
            let header = SinglePlayerNavigationHeader(subtitle: "Waiting for connection…",
                showsNativeFullscreen: true, enablesNativeFullscreen: false, isFocused: true,
                onMinimize: {}, onNativeFullscreen: {}, onExitFocus: {}, onClose: {})
                .environment(\.dynamicTypeSize, type)
                .environment(\.colorScheme, .dark)
                .frame(width: width)
            let host = UIHostingController(rootView: header)
            if type.isAccessibilitySize {
                host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            }
            let size = host.sizeThatFits(in: CGSize(width: width, height: 2_000))
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(size.height, 44)
            XCTAssertLessThan(size.height, 300, "Navigation must leave a viewport instead of reproducing the full long title")
            if width == 640 { XCTAssertLessThan(size.height, 150, "A short landscape window keeps space for its video") }
        }
    }

    func testSingleSourceSheetFitsMediumHeightWithAccessibleCheckingAndMultipleGroups() {
        let sessions = ["Score808", "AS1", "AS2", "CS1", "CS2"].map {
            StreamSession(matchID: "ui-only", playableURL: URL(string: "https://example.invalid/ui-only.m3u8")!,
                          streamType: .hls, providerName: $0)
        }
        var selected: [Int] = []
        let sheet = LiveStreamSelectorSheet(sessions: sessions, currentSourceIndex: .constant(1),
            failedSessionIDs: [], currentPlaybackMode: .native, isCheckingAdditionalSources: true,
            usesSinglePlayerPresentation: true, onSelect: { selected.append($0) })
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 320, height: 320)
        let host = UIHostingController(rootView: sheet)
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 320))
        XCTAssertEqual(size.width, 320, accuracy: 1)
        XCTAssertEqual(size.height, 320, accuracy: 1)
        XCTAssertTrue(selected.isEmpty, "Building or resizing source UI must not select or start any source")
    }

    func testSingleSourceCountFiltersAndChoicesShareOneScrollableOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let picker = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift"), encoding: .utf8)
        let start = try XCTUnwrap(picker.range(of: "private var singlePlayerSheet: some View"))
        let end = try XCTUnwrap(picker.range(of: "private var singleSourceFilters: some View"))
        let presentation = String(picker[start.lowerBound..<end.lowerBound])
        let scroll = try XCTUnwrap(presentation.range(of: "ScrollView {"))
        for child in ["Text(sourceSummary)", "singleSourceFilters", "joinedSourceChoices"] {
            XCTAssertTrue(presentation[scroll.upperBound...].contains(child), child)
        }
        let player = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Player/ViewingExperienceView.swift"), encoding: .utf8)
        let focusActions = try XCTUnwrap(player.range(of: "private func singleFocusActions"))
        let multiToolbar = try XCTUnwrap(player.range(of: "private var toolbar: some View"))
        let focus = String(player[focusActions.lowerBound..<multiToolbar.lowerBound])
        XCTAssertTrue(focus.contains("pane.model.showSourceSelector = true"))
        XCTAssertTrue(focus.contains("showsTabletDetails = true"))
        XCTAssertFalse(focus.contains("loadCurrentSource"))
        XCTAssertFalse(focus.contains("selectSourceManually"))
    }

    private func identity(title: String) -> SinglePlayerMatchIdentity {
        let event = EventReference(id: "ui-only", title: title, category: "football", date: nil,
                                   poster: nil, popular: nil, teams: nil, sources: nil)
        return SinglePlayerMatchIdentity(event: event, status: "Playing", scoreText: "1–1")
    }
}
