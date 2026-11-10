import SwiftUI
import XCTest

@testable import Fotty

@MainActor
final class Fotty25HomeDesignTests: XCTestCase {
    func testOverviewGivesWatchNowTheLargerColumnWithoutLosingWindowWidth() {
        for width: CGFloat in [1_000, 1_194, 1_366, 1_600] {
            let columns = HomeOverviewLayout.columnWidths(in: width)
            XCTAssertEqual(columns.primary + columns.secondary + 20, width, accuracy: 0.001)
            XCTAssertEqual(columns.primary / columns.secondary, 1.55, accuracy: 0.001)
            XCTAssertGreaterThan(columns.secondary, 360, "Upcoming matches retain a readable useful column")
        }
        XCTAssertFalse(FottyLayoutPolicy.usesColumns(width: 999))
        XCTAssertFalse(FottyLayoutPolicy.usesColumns(width: 1_194, accessibilitySize: true),
                       "Large text keeps the ordinary single-column reading order")
    }

    func testOverviewNeverProducesNegativeOrUnboundedChildWidths() {
        for width: CGFloat in [-10, 0, 10, .infinity, .nan] {
            let columns = HomeOverviewLayout.columnWidths(in: width)
            XCTAssertTrue(columns.primary.isFinite)
            XCTAssertTrue(columns.secondary.isFinite)
            XCTAssertGreaterThanOrEqual(columns.primary, 0)
            XCTAssertGreaterThanOrEqual(columns.secondary, 0)
        }
    }

    func testPhoneAndBoundedOverviewKeepThreeCoherentSportColumns() {
        let layout = SportTileGridLayout(minimumTileWidth: 88, spacing: 8, maximumColumns: 3)
        // A320pt phone proposes288pt after the real16pt outer insets.
        for width: CGFloat in [288, 320, 343, 361, 398, 430] {
            let metrics = layout.metrics(width: width, count: 6)
            XCTAssertEqual(metrics.columns, 3)
            XCTAssertEqual(metrics.rows, 2)
            XCTAssertEqual(metrics.origin(at: 2).x + metrics.tileWidth, width, accuracy: 0.001)
        }
        XCTAssertEqual(layout.metrics(width: 200, count: 6).columns, 2,
                       "An actually narrow or expanded-text proposal reflows rather than shrinking its contents")
    }

    func testApprovedHomeCompositionKeepsLazyCatalogAndExistingActions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        let rows = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"), encoding: .utf8)
        XCTAssertTrue(dashboard.contains("ForEach(entries)"))
        XCTAssertTrue(dashboard.contains("HomeSportsDiscovery.displayRows(items, columns: columns, section: section)"))
        XCTAssertTrue(dashboard.contains("homeScheduleRow(item)"))
        XCTAssertTrue(dashboard.contains("HomeMatchGroupShape(isFirst: wide || index == 0"))
        XCTAssertTrue(dashboard.contains("isLast: wide || index == row.total - 1"))
        XCTAssertTrue(dashboard.contains("browseSportsSection(discovery, compact: true)"))
        XCTAssertTrue(rows.contains("detailsExpanded: inlineContext.isExpanded(for: item.id)"))
        XCTAssertTrue(rows.contains("MatchStartControls("))
        XCTAssertTrue(rows.contains(".onChange(of: item.id) { _, _ in inlineContext.reset() }"))
        let scheduleStart = try XCTUnwrap(rows.range(of: "struct HomeScheduleRow: View"))
        let schedule = rows[scheduleStart.lowerBound...]
        XCTAssertTrue(schedule.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(schedule.contains(".lineLimit(nil)"), "Long team identity must remain readable")
        XCTAssertFalse(schedule.contains("minimumScaleFactor"))
        XCTAssertFalse(schedule.contains(".truncationMode(.middle)"))
    }

    func testViewingDurationFallsBackForActualNarrowCardWidthWithoutChangingChoices() {
        // A320pt phone's card leaves256pt after screen/card16pt side insets.
        XCTAssertTrue(MatchdayDurationControl.usesMenu(width: 256, wideLayout: false, accessibilitySize: false))
        XCTAssertFalse(MatchdayDurationControl.usesMenu(width: 329, wideLayout: false, accessibilitySize: false))
        XCTAssertTrue(MatchdayDurationControl.usesMenu(width: 600, wideLayout: true, accessibilitySize: false))
        XCTAssertTrue(MatchdayDurationControl.usesMenu(width: 600, wideLayout: false, accessibilitySize: true))
        XCTAssertTrue(MatchdayDurationControl.usesMenu(width: .nan, wideLayout: false, accessibilitySize: false))
        XCTAssertEqual(ViewingPlanDuration.allCases.map(\.title), ["90 min", "2 hours", "Until midnight"])
        XCTAssertEqual(ViewingPlanDuration.saved("2-hours"), .twoHours)
    }

    func testAdaptiveHeadingsAndRootInjectionKeepExistingPresentationOwners() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dashboard = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        let matchday = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Social/ArenaDiscoveryView.swift"), encoding: .utf8)
        let rows = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"), encoding: .utf8)
        XCTAssertTrue(dashboard.contains("CatalogAdaptiveHeading {"))
        XCTAssertTrue(matchday.contains("CatalogAdaptiveHeading {"))
        XCTAssertTrue(rows.contains("title.fixedSize(horizontal: true, vertical: true)"))
        XCTAssertTrue(rows.contains("actions.fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(matchday.contains("MatchdayDurationControl(selection: $viewingDurationRaw, usesWideLayout: usesWideLayout)"))
        XCTAssertTrue(dashboard.contains("self._matchListViewModel = State(initialValue: matchListViewModel)"))
        XCTAssertTrue(matchday.contains("self._myMatchdayStore = State(initialValue: myMatchdayStore ?? .shared)"))
        XCTAssertTrue(dashboard.contains("matchListViewModel = MatchListViewModel.shared"), "Normal Home keeps the established fallback owner")
        XCTAssertTrue(matchday.contains("myMatchdayStore: MyMatchdayStore? = nil"))
        XCTAssertTrue(matchday.contains("self._matchListViewModel = State(initialValue: matchListViewModel ?? .shared)"),
                      "Normal Matchday resolves the established defaults on the main actor")
        XCTAssertTrue(matchday.contains("guard !AppRuntime.isAutomatedTesting, isActive, scenePhase == .active"))
    }

    func testNarrowSavedSpotlightKeepsAReadableNaturalWatchButton() throws {
        let watch = try spotlightActionBounds(title: "Watch")
        XCTAssertGreaterThanOrEqual(watch.width, 100, "Saved/time and More must not squeeze Watch into a vertical pill")
        XCTAssertGreaterThanOrEqual(watch.height, 40)
        XCTAssertLessThan(watch.height, 65, "An ordinary Watch label should remain a single readable line")

        let longAction = try spotlightActionBounds(title: "Check available match broadcasts")
        XCTAssertGreaterThanOrEqual(longAction.width, 180)
        XCTAssertGreaterThanOrEqual(longAction.height, 40)
        XCTAssertLessThan(longAction.height, 130, "A long action reflows within the card rather than collapsing to one character per line")
    }

    func testTrulyEmptyHomeUsesExistingRecoveryBeforeBrowseWithoutChangingMultiSelection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/SportsDashboardView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("selectionIsEmpty: items.isEmpty && channelEvents(applyingHomeInterests: true).isEmpty"))
        let emptyGuard = try XCTUnwrap(source.range(of: "if selectionIsEmpty {"))
        let recovery = try XCTUnwrap(source.range(of: "entries.append(.selectionEmpty)", range: emptyGuard.lowerBound..<source.endIndex))
        let heading = try XCTUnwrap(source.range(of: "entries.append(.heading(.upcoming, \"Up Next\"))", range: recovery.upperBound..<source.endIndex))
        let browse = try XCTUnwrap(source.range(of: "entries.append(.browseSports)", range: heading.upperBound..<source.endIndex))
        XCTAssertLessThan(recovery.lowerBound, heading.lowerBound)
        XCTAssertLessThan(heading.lowerBound, browse.lowerBound)
        XCTAssertTrue(source[recovery.upperBound..<heading.lowerBound].contains("} else if !sections.upcoming.isEmpty || sections.nextClub == nil {"),
                      "Empty selections use recovery; an already featured next-club fixture need not duplicate an empty Up Next section")
        XCTAssertTrue(source.contains("if isMultiSelectMode && items.isEmpty && channelEvents(applyingHomeInterests: true).isEmpty"),
                      "The existing multi-selection empty presentation remains outside the normal Home entry list")
        XCTAssertTrue(source.contains("case .selectionEmpty:\n            emptyState(applyingHomeInterests: true)"))
        XCTAssertFalse(source.contains("\"Also live\""),
                       "A listed broadcast alone must not make its section claim verified live status")
        XCTAssertTrue(source.contains("\"More events\""))
    }

    private func spotlightActionBounds(title: String?) throws -> CGRect {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let event = EventReference(id: "home-footer-layout-only", title: "Render Home vs Render Away", category: "cricket",
            date: Int64(now.addingTimeInterval(-1_800).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Render Home", badge: nil), away: .init(name: "Render Away", badge: nil)))
        let item = try XCTUnwrap(HomeSportsDiscovery(events: [event], now: now).items.first)
        let image = try FottyHostedViewSnapshot.image(
            HomeLiveSpotlight(item: item, presentation: .init(item: item), now: now, isSaved: true,
                              onOpen: { XCTFail("A layout test must not open playback") }, onSave: {}, alternateActionTitle: title)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .large),
            width: 288, scheme: .dark, type: .large)
        let pixels = try FottyVisualPixelComparison.Pixels(image: image)
        var minX = pixels.width, minY = pixels.height, maxX = -1, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let index = (y * pixels.width + x) * 4
                if pixels.rgba[index] > 190, pixels.rgba[index + 1] > 110,
                   pixels.rgba[index + 1] < 210, pixels.rgba[index + 2] < 70 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "The genuine Watch button must be visible in the native component render")
        let attachment = XCTAttachment(image: image)
        attachment.name = title == "Watch" ? "home-footer-saved-time-narrow" : "home-footer-long-action-narrow"
        attachment.lifetime = .keepAlways
        add(attachment)
        return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                      width: CGFloat(max(0, maxX - minX + 1)), height: CGFloat(max(0, maxY - minY + 1)))
    }
}
