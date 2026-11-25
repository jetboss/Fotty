import XCTest
import SwiftUI
@testable import Fotty

@MainActor
final class Fotty25SecondaryDesignTests: XCTestCase {
    private final class TileMeasurements {
        var sizes: [String: CGSize] = [:]
    }

    func testSearchSportButtonSurfacesShareMeasuredHeightWithWrappedNames() throws {
        let sports = [("football", "Football"), ("american-football", "American football"), ("basketball", "Basketball")]
        for (width, type) in [(CGFloat(288), DynamicTypeSize.large), (343, .large),
                              (680, .large), (288, .accessibility2)] {
            for scheme in [ColorScheme.dark, .light] {
                let measured = TileMeasurements()
                let grid = SportTileGridLayout(minimumTileWidth: type.isAccessibilitySize ? 220 : 94,
                    maximumColumns: type.isAccessibilitySize ? 1 : 3) {
                    ForEach(sports, id: \.0) { sport in
                        Button {} label: {
                            SportsSearchSportTileLabel(category: sport.0, title: sport.1)
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { measured.sizes[sport.0] = $0 }
                        }
                        .buttonStyle(FottyPressButtonStyle())
                    }
                }
                .environment(\.dynamicTypeSize, type)
                .environment(\.colorScheme, scheme)
                let image = try FottyHostedViewSnapshot.image(grid, width: width, scheme: scheme, type: type)
                XCTAssertEqual(measured.sizes.count, sports.count)
                let heights = sports.compactMap { measured.sizes[$0.0]?.height }
                let commonHeight = try XCTUnwrap(heights.max())
                XCTAssertGreaterThanOrEqual(commonHeight, 76)
                for sport in sports {
                    XCTAssertEqual(try XCTUnwrap(measured.sizes[sport.0]).height, commonHeight, accuracy: 0.5,
                                   "The painted \(sport.1) surface must fill its measured cell at \(width)pt/\(type)")
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Search actual sport labels \(Int(width))pt \(type) \(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testNarrowSettingWithLongValueReflowsInsteadOfSqueezingItsName() {
        XCTAssertTrue(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 256,
            labelIdealWidth: 240, accessoryIdealWidth: 112, accessibilitySize: false))
    }

    func testOrdinarySettingRetainsLabelAndValueOnOneRow() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 320,
            labelIdealWidth: 220, accessoryIdealWidth: 82, accessibilitySize: false))
    }

    func testWideSettingDoesNotStackJustBecauseItsTitleIsLong() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 480,
            labelIdealWidth: 550, accessoryIdealWidth: 130, accessibilitySize: false))
    }

    func testShortSettingLabelCanUseItsActualRequiredRoom() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 244,
            labelIdealWidth: 85, accessoryIdealWidth: 130, accessibilitySize: false))
    }

    func testAccessibilitySettingAlwaysPlacesValueBelowItsLabel() {
        XCTAssertTrue(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 1_180,
            labelIdealWidth: 160, accessoryIdealWidth: 82, accessibilitySize: true))
    }

    func testPassiveSettingDoesNotReserveAnEmptyAccessoryRow() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 256,
            labelIdealWidth: 240, accessoryIdealWidth: 0, accessibilitySize: true))
    }

    func testNativeToggleHasComfortableRoomAlongsideAnOrdinaryLabel() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 288,
            labelIdealWidth: 220, accessoryIdealWidth: 51, accessibilitySize: false))
    }

    func testRootDisclosureAloneDoesNotCreateAnAccessibilityAccessoryLine() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 256,
            labelIdealWidth: 440, accessoryIdealWidth: 18, accessibilitySize: true,
            hasStackableAccessory: false))
    }

    func testRootDisclosureLeavesNarrowLabelWrappingInItsOwnRow() {
        XCTAssertFalse(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 180,
            labelIdealWidth: 240, accessoryIdealWidth: 18, accessibilitySize: false,
            hasStackableAccessory: false))
    }

    func testRealValuesAndNativeTogglesKeepAccessibilityReflow() {
        for accessoryWidth in [CGFloat(51), CGFloat(112)] {
            XCTAssertTrue(SettingsAccessoryLayoutPolicy.stacks(availableWidth: 320,
                labelIdealWidth: 240, accessoryIdealWidth: accessoryWidth, accessibilitySize: true,
                hasStackableAccessory: true))
        }
    }
}
