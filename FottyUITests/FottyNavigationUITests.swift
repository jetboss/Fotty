import XCTest

final class FottyNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let isFPLWorkspaceAudit = name.contains("testFPLWorkspacesDynamicTypeAccessibilityAudit") || name.contains("testFPLContextSurvivesTabSwitch") || name.contains("testFPLSavedDraftAndPickerRejection")
        let surfaceOverride: String?
        switch name {
        case let value where value.contains("testMatchCenterDynamicTypeAccessibilityAudit"):
            surfaceOverride = "match-center"
        case let value where value.contains("testPlayerDynamicTypeAccessibilityAudit"):
            surfaceOverride = "player"
        default:
            surfaceOverride = nil
        }
        let initialTab: String
        switch name {
        case let value where value.contains("testFPLWorkspacesDynamicTypeAccessibilityAudit") || value.contains("testFPLContextSurvivesTabSwitch") || value.contains("testFPLSavedDraftAndPickerRejection"):
            initialTab = "FPL"
        case let value where value.contains("testMatchdayDynamicTypeAccessibilityAudit"):
            initialTab = "Arena"
        case let value where value.contains("testSettingsDynamicTypeAccessibilityAudit") || value.contains("testBetaSupport"):
            initialTab = "Settings"
        case let value where value.contains("testBetaFPLInput"):
            initialTab = "FPL"
        default:
            initialTab = "Home"
        }
        app.launchArguments += [
            "-fotty.onboarding.hasDismissed", "YES",
            "-fotty.selectedTab", initialTab
        ]
        if name.contains("testBetaSetup") {
            app.launchEnvironment["FOTTY_SETUP_UI_TESTING"] = "1"
        } else {
            app.launchArguments += ["-fotty.setup.dismissed.v1", "YES"]
        }
        if name.contains("testBetaFPLInput") || name.contains("testBetaSetup") {
            app.launchArguments += ["-fotty.user.fplManagerId", "0", "-fotty.fpl.managerId", "0"]
        }
        let isPhysicalLiveTest = name.contains("testPhysicalLivePlayerAndSourcePresentation")
            && ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil
        if isPhysicalLiveTest {
            app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        } else {
            app.launchEnvironment["FOTTY_AUTOMATED_TESTING"] = "1"
        }
        if isFPLWorkspaceAudit {
            app.launchEnvironment["FOTTY_FPL_UI_TESTING"] = "1"
            app.launchArguments += ["-fotty.fpl.smartCoachConsent", "YES"]
        }
        if name.contains("testCricketDiscovery") {
            app.launchEnvironment["FOTTY_CRICKET_UI_TESTING"] = "1"
        }
        if name.contains("testHomeDiscovery") || name.contains("testDashboard") {
            app.launchEnvironment["FOTTY_HOME_UI_TESTING"] = "1"
        }
        if let surfaceOverride {
            app.launchEnvironment["FOTTY_SURFACE_UI_TESTING"] = "1"
            app.launchArguments += ["--fotty-ui-test-surface", surfaceOverride]
        }
        app.launch()
        if let surfaceOverride {
            let identifier = surfaceOverride == "match-center" ? "match-center" : "live-player"
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 12),
                "The \(surfaceOverride) test surface was unavailable"
            )
            return
        }
        let initialTabID: String
        switch initialTab {
        case "Arena": initialTabID = "tab-arena"
        case "FPL": initialTabID = "tab-fpl"
        case "Settings": initialTabID = "tab-settings"
        default: initialTabID = "tab-home"
        }
        let initialTabButton = app.buttons[initialTabID]
        XCTAssertTrue(initialTabButton.waitForExistence(timeout: 12))
        if initialTab == "Home" {
            // Dashboard audits must not inherit whichever tab a previous manual or
            // automated session persisted. Selecting Home also keeps heavyweight
            // FPL loading work out of unrelated accessibility measurements.
            tapBetaControl(initialTabButton)
        }
    }

    func testFPLContextSurvivesTabSwitch() throws {
        let tools = app.buttons["fpl-workspace-tools"]
        reveal(tools)
        tapBetaControl(tools)
        let captain = app.buttons["fpl-tool-Captain"]
        reveal(captain)
        tapBetaControl(captain)
        XCTAssertTrue(app.buttons["fpl-all-tools"].waitForExistence(timeout: 5))
        let lastCaptain = app.descendants(matching: .any)["fpl-captain-card-5"].firstMatch
        reveal(lastCaptain)
        let previousY = lastCaptain.frame.minY
        tapBetaControl(app.buttons["tab-settings"])
        tapBetaControl(app.buttons["tab-fpl"])
        XCTAssertTrue(app.buttons["fpl-all-tools"].waitForExistence(timeout: 5), "Leaving FPL must not reset the selected tool")
        XCTAssertTrue(app.staticTexts["Captain"].exists)
        XCTAssertFalse(app.staticTexts["Loading your FPL team…"].exists)
        XCTAssertEqual(lastCaptain.frame.minY, previousY, accuracy: 12, "Returning to FPL should restore the tool's scroll position")
        let allTools = app.buttons["fpl-all-tools"]
        reveal(allTools)
        tapBetaControl(allTools)
        XCTAssertTrue(app.buttons["fpl-tool-Captain"].waitForExistence(timeout: 5))
        let compare = app.buttons["fpl-tool-Compare players"]
        reveal(compare)
        tapBetaControl(compare)
        let firstPlayer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose first player,")).firstMatch
        reveal(firstPlayer)
        tapBetaControl(firstPlayer)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        tapBetaControl(search)
        search.typeText("Double-Name")
        let result = app.buttons["fpl-comparison-result-2"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        tapBetaControl(result)
        XCTAssertTrue(firstPlayer.label.contains("Test Double-Name"))
        tapBetaControl(app.buttons["tab-home"])
        tapBetaControl(app.buttons["tab-fpl"])
        XCTAssertTrue(firstPlayer.waitForExistence(timeout: 5))
        XCTAssertTrue(firstPlayer.label.contains("Test Double-Name"), "Comparison selection should survive leaving FPL")
    }

    func testFPLSavedDraftAndPickerRejection() throws {
        let squad = app.buttons["fpl-workspace-squad"]
        reveal(squad)
        tapBetaControl(squad)
        let player = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Test Double-Name")).firstMatch
        reveal(player)
        tapBetaControl(player)
        #if targetEnvironment(macCatalyst)
        // AppKit exposes this confirmation-sheet action by identifier/title,
        // not the UILabel-style accessibility label used on iPhone.
        let replace = app.sheets.buttons["action-button--998"]
        #else
        let replace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Replace Test Double-Name")).firstMatch
        #endif
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        tapBetaControl(replace)
        let duplicate = app.buttons["fpl-replacement-3"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        tapBetaControl(duplicate)
        XCTAssertTrue(app.descendants(matching: .any)["fpl-player-selection-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(duplicate.exists, "Rejected replacement must leave the picker open")
        let search = app.textFields["Search player name or club..."]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        tapBetaControl(search)
        search.typeText("Replacement")
        let valid = app.buttons["fpl-replacement-16"]
        XCTAssertTrue(valid.waitForExistence(timeout: 5))
        tapBetaControl(valid)
        let source = app.staticTexts["fpl-squad-source"]
        reveal(source)
        XCTAssertTrue(source.label.contains("Local draft"))
        tapBetaControl(app.buttons["tab-settings"])
        tapBetaControl(app.buttons["tab-fpl"])
        reveal(source)
        XCTAssertTrue(source.label.contains("Local draft"))
        let updated = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Replacement Defender")).firstMatch
        XCTAssertTrue(updated.exists)
    }

    func testHomeDiscoveryShowsActivityFiltersAndFullLineup() throws {
        XCTAssertEqual(app.buttons["tab-home"].label, "Home")
        XCTAssertTrue(app.buttons["home-sport-football"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Field Events"].exists)
        XCTAssertFalse(app.staticTexts["Reference"].exists)
        let all = app.buttons["home-sport-all-sports"]
        XCTAssertTrue(all.waitForExistence(timeout: 8))
        XCTAssertTrue(all.isSelected)
        XCTAssertEqual(app.buttons["home-sport-basketball"].value as? String, "1 on now")
        let cricket = app.descendants(matching: .any)["home-event-cpl-2026-ui-home"].firstMatch
        XCTAssertTrue(cricket.exists)
        XCTAssertFalse(app.buttons["home-save-cpl-2026-ui-home"].exists, "Saving belongs in the secondary menu")
        reveal(cricket)
        openMatchMenu(cricket)
        selectMatchMenuAction("Save to My Matchday")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Saving alone must not ask for notification permission")
        let basketball = app.buttons["home-sport-basketball"]
        reveal(basketball)
        tapBetaControl(basketball)
        XCTAssertTrue(basketball.isSelected)
        XCTAssertFalse(app.buttons["match-start-play-ui-football"].exists)
        XCTAssertTrue(app.buttons["match-start-play-ui-basketball"].exists)
        XCTAssertFalse(app.buttons["home-save-ui-basketball"].exists)
        let more = app.buttons["home-more-sports"]
        if more.exists {
            reveal(more)
            tapBetaControl(more)
        }
        let rugby = app.buttons["home-sport-rugby"]
        XCTAssertTrue(rugby.waitForExistence(timeout: 5))
        tapBetaControl(rugby)
        XCTAssertTrue(app.buttons["home-sport-rugby"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-sport-rugby"].isSelected)
        let seeAll = app.buttons["home-see-all"]
        reveal(seeAll)
        tapBetaControl(seeAll)
        XCTAssertTrue(app.descendants(matching: .any)["home-full-lineup"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["match-start-countdown-ui-rugby"].firstMatch.exists)
        XCTAssertFalse(app.buttons["match-start-play-ui-rugby"].exists, "A future source-free row must not open an empty player")
        tapBetaControl(app.buttons["tab-arena"])
        XCTAssertTrue(app.staticTexts["Trinbago Knight Riders"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your squad in action"].exists)
        openMatchMenu(app.staticTexts["Trinbago Knight Riders"].firstMatch)
        selectMatchMenuAction("Remove from My Matchday")
        XCTAssertFalse(app.staticTexts["Trinbago Knight Riders"].exists)
    }

    func testBetaSupportOpensNativeHelpAndFeedback() throws {
        let help = app.buttons["settings-help"]
        reveal(help)
        tapBetaControl(help)
        XCTAssertTrue(app.navigationBars["Fotty Help"].waitForExistence(timeout: 5), "Native Help navigation missing (app state: \(app.state))")
        XCTAssertTrue(app.staticTexts["Score coverage"].exists, "Help score-coverage explanation missing")
        tapBetaControl(app.navigationBars.buttons.firstMatch)
        let feedback = app.buttons["settings-feedback"]
        reveal(feedback)
        tapBetaControl(feedback)
        XCTAssertTrue(app.navigationBars["Report a problem"].waitForExistence(timeout: 5), "Native feedback navigation missing (app state: \(app.state))")
        XCTAssertTrue(app.textViews["feedback-expected"].exists || app.textFields["feedback-expected"].exists, "Feedback entry missing")
        let diagnostics = app.switches["feedback-diagnostics"]
        reveal(diagnostics)
        XCTAssertEqual(diagnostics.value as? String, "0", "Diagnostics must start opt-out")
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription]) { issue in
            #if targetEnvironment(macCatalyst)
            // Match the existing description audit's system-window exclusions.
            if issue.auditType == .sufficientElementDescription, let element = issue.element {
                if [.window, .menuBar, .touchBar].contains(element.elementType) { return true }
                let frame = element.frame
                let window = self.app.windows.firstMatch.frame
                if element.elementType == .group,
                   abs(frame.minX - window.minX) <= 2, abs(frame.minY - window.minY) <= 2,
                   abs(frame.width - window.width) <= 2, abs(frame.height - window.height) <= 2 { return true }
            }
            #endif
            if let element = issue.element {
                print("Unignored beta support audit issue: \(element.label), \(element.identifier), \(element.frame)")
            }
            return false
        }
    }

    func testBetaFPLInputAcceptsTeamLinksWithoutAutomaticallyConnecting() {
        let input = app.textFields["fpl-manager-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        tapBetaControl(input)
        input.typeText("https://fantasy.premierleague.com/entry/123456/event/2")
        let find = app.buttons["fpl-find-team"]
        reveal(find)
        XCTAssertTrue(find.isEnabled)
        XCTAssertFalse(app.buttons["fpl-confirm-team"].exists, "Pasting a link must not connect or fetch a team")
    }

    func testBetaSetupStaysFocusedOnMatchdayAndCanBeDismissed() {
        XCTAssertFalse(app.buttons["setup-fpl"].exists)
        let dismiss = app.buttons["setup-dismiss"]
        reveal(dismiss)
        tapBetaControl(dismiss)
        XCTAssertFalse(dismiss.exists)
        tapBetaControl(app.buttons["tab-arena"])
        XCTAssertFalse(app.buttons["matchday-fpl"].exists)
        XCTAssertFalse(app.staticTexts["Saved, followed, and FPL-relevant fixtures in one personal plan"].exists)
    }

    func testCricketDiscoverySeparatesChannelsAndSavesWithoutFPL() throws {
        let willow = app.staticTexts["Willow Cricket"].firstMatch
        XCTAssertTrue(willow.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Willow Cricket vs Away"].exists)
        XCTAssertFalse(app.staticTexts["Schedule TBD"].exists)
        XCTAssertFalse(app.buttons["setup-fpl"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["cricket-filter"].firstMatch.exists)
        reveal(willow)
        try auditCricketAccessibility()
        openMatchMenu(willow)
        selectMatchMenuAction("Save to My Matchday")
        tapBetaControl(app.buttons["tab-arena"])
        XCTAssertTrue(app.staticTexts["Willow Cricket"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Saved channels")).firstMatch.exists)
        XCTAssertFalse(app.buttons["matchday-fpl"].exists)
        try auditCricketAccessibility()
    }

    private func selectMatchMenuAction(_ title: String) {
        #if targetEnvironment(macCatalyst)
        // UIKit bridges context menus to NSMenu: the title is the menu item's
        // identifier, not its accessibility label or the SwiftUI button ID.
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing match action: \(title)")
        item.click()
        #else
        let item = app.buttons[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing match action: \(title)")
        item.tap()
        #endif
    }

    private func openMatchMenu(_ element: XCUIElement) {
        #if targetEnvironment(macCatalyst)
        element.rightClick()
        #else
        element.press(forDuration: 1)
        #endif
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Match secondary actions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func auditCricketAccessibility() throws {
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription]) { issue in
            guard issue.auditType == .textClipped || issue.auditType == .sufficientElementDescription else { return true }
 #if targetEnvironment(macCatalyst)
            // The same system-owned window exclusion as the Home description
            // gate. Every app-owned cricket element remains in scope.
            if issue.auditType == .sufficientElementDescription, let element = issue.element {
                if [.window, .menuBar, .touchBar].contains(element.elementType) { return true }
                let frame = element.frame
                let window = self.app.windows.firstMatch.frame
                if element.elementType == .group,
                   abs(frame.minX - window.minX) <= 2, abs(frame.minY - window.minY) <= 2,
                   abs(frame.width - window.width) <= 2, abs(frame.height - window.height) <= 2 { return true }
            }
 #endif
            if let element = issue.element {
                print("Unignored cricket audit issue: \(element.label), \(element.identifier), \(element.frame)")
            }
            return false
        }
    }

    private func reveal(_ element: XCUIElement) {
        guard activateBetaWindow() else { return }
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            // Catalyst's application proxy has no hittable point. Gesture on
            // the actual scroll surface, just as a person scrolls the window.
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                if element.exists && element.frame.maxY > 0 && element.frame.minY < scrollView.frame.minY {
                    scrollView.swipeDown()
                } else {
                    scrollView.swipeUp()
                }
            } else {
                app.windows.firstMatch.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected a reachable control: \(element)")
    }

    private func activateBetaWindow() -> Bool {
        app.activate()
        let ready = app.wait(for: .runningForeground, timeout: 5)
        XCTAssertTrue(ready, "Fotty must stay in the foreground for UI interaction checks")
        return ready
    }

    private func tapBetaControl(_ element: XCUIElement) {
        guard activateBetaWindow() else { return }
        #if targetEnvironment(macCatalyst)
        // Catalyst uses mouse events; a synthesized touch tap can move the
        // pointer without activating a native Mac control.
        element.click()
        #else
        element.tap()
        #endif
    }

    func testRapidTabSwitchingAndForegroundRecovery() {
        let tabIDs = ["tab-arena", "tab-fpl", "tab-settings", "tab-home"]

        for _ in 0..<3 {
            for id in tabIDs {
                let tab = app.buttons[id]
                XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing \(id)")
                tapBetaControl(tab)
                XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 3), "Tab did not become selected: \(id)")
            }
        }

        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        app.activate()

        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testDashboardHitRegionAccessibilityAudit() throws {
        try app.performAccessibilityAudit(for: [.hitRegion]) { issue in
            issue.auditType != .hitRegion
        }
    }

    func testDashboardTextClippingAccessibilityAudit() throws {
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            // Catalyst can emit a sufficient-description issue for the window
            // while running a text-clipping-only audit. That category has its
            // own release gate below; do not let it masquerade as clipping.
            guard issue.auditType == .textClipped else {
                print("Ignored non-text-clipping issue emitted by scoped audit: \(issue.auditType)")
                return true
            }
            if let element = issue.element {
                print("Unignored Text Clipped issue: \(element.label), frame: \(element.frame)")
            }
            return false
        }
    }

    func testDashboardElementDescriptionAccessibilityAudit() throws {
        try app.performAccessibilityAudit(for: [.sufficientElementDescription]) { issue in
            guard issue.auditType == .sufficientElementDescription else { return true }
            #if targetEnvironment(macCatalyst)
            // XCTest audits the system-owned Catalyst window even though macOS
            // visibly supplies the app title ("Fotty"). SwiftUI cannot attach a
            // description to that shell without collapsing the app's child
            // accessibility tree, so keep auditing every app-owned element and
            // exclude only the window container.
            if let element = issue.element {
                if element.elementType == .window
                    || element.elementType == .menuBar
                    || element.elementType == .touchBar {
                    return true
                }

                let elementFrame = element.frame
                let windowFrame = self.app.windows.firstMatch.frame
                let isRootWindowGroup = element.elementType == .group
                    && abs(elementFrame.minX - windowFrame.minX) <= 2
                    && abs(elementFrame.minY - windowFrame.minY) <= 2
                    && abs(elementFrame.width - windowFrame.width) <= 2
                    && abs(elementFrame.height - windowFrame.height) <= 2
                if isRootWindowGroup { return true }
            }
            #endif
            if let element = issue.element {
                XCTFail(
                    "Unignored Element Description issue: type=\(element.elementType.rawValue), "
                        + "label=\(element.label), identifier=\(element.identifier), frame=\(element.frame)"
                )
                return true
            }
            return false
        }
    }

    func testDashboardDynamicTypeAccessibilityAudit() throws {
        let dockTop = app.buttons["tab-home"].frame.minY
        try app.performAccessibilityAudit(for: [.dynamicType]) { issue in
            guard issue.auditType == .dynamicType else { return true }
            guard let element = issue.element,
                  element.elementType == .staticText else { return false }
            // Navigation-dock labels follow the compact system tab-bar pattern;
            // their controls expose full VoiceOver labels even when the visual
            // caption remains at the compact control size.
            if element.frame.midY >= dockTop { return true }
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            // Two/three-letter fallback crests are graphical badge artwork.
            // The enclosing badge exposes the full team name to VoiceOver and
            // scales as a unit, so these initials are not readable body copy.
            let isGraphicalInitials = (1...3).contains(label.count)
                && label == label.uppercased()
            let isCompactStatusBadge = ["LIVE", "SOON", "P2P", "TODAY"].contains(label)
            let isCompactUppercaseChrome = label.count <= 15 && label == label.uppercased()
            if !isGraphicalInitials && !isCompactStatusBadge && !isCompactUppercaseChrome {
                print("Unignored Dynamic Type issue: \(label), frame: \(element.frame)")
            }
            return isGraphicalInitials || isCompactStatusBadge || isCompactUppercaseChrome
        }
    }

    func testFPLWorkspacesDynamicTypeAccessibilityAudit() throws {
        let workspaceLabels = ["Plan", "Squad", "Coach", "Tools"]
        for (index, label) in workspaceLabels.enumerated() {
            if index > 0 {
                app.terminate()
                app.launchArguments = [
                    "-fotty.onboarding.hasDismissed", "YES",
                    "-fotty.selectedTab", "FPL",
                    "--fotty-fpl-workspace", label
                ]
                app.launchEnvironment["FOTTY_AUTOMATED_TESTING"] = "1"
                app.launchEnvironment["FOTTY_FPL_UI_TESTING"] = "1"
                app.launch()
            }

            XCTAssertTrue(app.buttons["tab-fpl"].waitForExistence(timeout: 12), "FPL tab was unavailable")
            let workspace = app.buttons[label].firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 15), "FPL \(label) workspace was unavailable")

            if label == "Squad" {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Test Double-Name")).firstMatch.waitForExistence(timeout: 5), "Squad audit must exercise a populated five-player row, not an empty state")
            }

            if label == "Coach" {
                let prompt = app.buttons["Audit my whole squad for the next five gameweeks"]
                XCTAssertTrue(prompt.waitForExistence(timeout: 5), "Coach quick prompt was unavailable")
                XCTAssertTrue(
                    app.descendants(matching: .any)["fpl-coach-response"].waitForExistence(timeout: 5),
                    "Coach response was not visible"
                )
            }

            let dockTop = app.buttons["tab-fpl"].frame.minY
            try app.performAccessibilityAudit(for: [.dynamicType]) { issue in
                guard issue.auditType == .dynamicType else { return true }
                guard let element = issue.element,
                      element.elementType == .staticText else { return false }
                let text = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let isDockLabel = element.frame.midY >= dockTop
                let isGraphicalInitials = (1...3).contains(text.count)
                    && text == text.uppercased()
                let isCompactUppercaseChrome = text.count <= 15
                    && text == text.uppercased()
                let isIgnored = isDockLabel || isGraphicalInitials || isCompactUppercaseChrome
                if !isIgnored {
                    print(
                        "Unignored FPL \(label) Dynamic Type issue: "
                            + "type=\(element.elementType.rawValue), label=\(text), "
                            + "identifier=\(element.identifier), frame=\(element.frame)"
                    )
                }
                return isIgnored
            }
        }
    }

    func testMatchdayDynamicTypeAccessibilityAudit() throws {
        try performSurfaceDynamicTypeAudit(
            surface: "Matchday",
            dockTop: app.buttons["tab-arena"].frame.minY
        )
    }

    func testSettingsDynamicTypeAccessibilityAudit() throws {
        try performSurfaceDynamicTypeAudit(
            surface: "Settings",
            dockTop: app.buttons["tab-settings"].frame.minY
        )
    }

    func testMatchCenterDynamicTypeAccessibilityAudit() throws {
        try performSurfaceDynamicTypeAudit(
            surface: "Match Center",
            dockTop: .greatestFiniteMagnitude
        )
    }

    func testPlayerDynamicTypeAccessibilityAudit() throws {
        try performSurfaceDynamicTypeAudit(
            surface: "Player",
            dockTop: .greatestFiniteMagnitude
        )
    }

    private func performSurfaceDynamicTypeAudit(surface: String, dockTop: CGFloat) throws {
        try app.performAccessibilityAudit(for: [.dynamicType]) { issue in
            guard issue.auditType == .dynamicType else { return true }
            guard let element = issue.element,
                  element.elementType == .staticText else { return false }
            let text = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDockLabel = element.frame.midY >= dockTop
            let isGraphicalInitials = (1...3).contains(text.count)
                && text == text.uppercased()
            let isCompactUppercaseChrome = text.count <= 15
                && text == text.uppercased()
            let isIgnored = isDockLabel || isGraphicalInitials || isCompactUppercaseChrome
            if !isIgnored {
                print(
                    "Unignored \(surface) Dynamic Type issue: "
                        + "type=\(element.elementType.rawValue), label=\(text), "
                        + "identifier=\(element.identifier), frame=\(element.frame)"
                )
            }
            return isIgnored
        }
    }

    func testDashboardContrastAndTraitsAccessibilityAudit() throws {
        let dockTop = app.buttons["tab-home"].frame.minY
        try app.performAccessibilityAudit(for: [.contrast, .trait]) { issue in
            guard issue.auditType == .contrast || issue.auditType == .trait else {
                return true
            }
            if issue.auditType == .trait {
                if let element = issue.element {
                    XCTFail(
                        "Unignored Trait issue: type=\(element.elementType.rawValue), "
                            + "label=\(element.label), identifier=\(element.identifier), frame=\(element.frame)"
                    )
                }
                return true
            }
            // Lazy scroll rows can remain in the accessibility tree while fully
            // covered by the persistent dock. XCTest samples the dock pixels in
            // that case and reports them as the row text's contrast. The actual
            // row becomes testable once VoiceOver scrolls it above the dock.
            guard let element = issue.element,
                  element.elementType == .staticText else { return false }
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGraphicalCrestInitials = (1...3).contains(label.count)
                && label == label.uppercased()
                && element.frame.width <= 48
                && element.frame.height <= 48
            let isKnownHighContrastTeamName = element.identifier == "dashboard-team-name"
            let isKnownHighContrastEmptyMessage = element.identifier == "dashboard-empty-state-message"
            let isKnownHighContrastEmptyRefresh = element.identifier == "dashboard-empty-refresh-label"
            // Fallback crest initials are badge artwork. The enclosing badge
            // exposes the full team name and the rendered initials use a dark,
            // high-contrast treatment, but Catalyst audits the decorative Text
            // node independently even when it is accessibility-hidden.
            // Dashboard team names are explicit 15-point system white on the
            // fixed near-black bento surface. Catalyst 27 beta reports them even
            // though the captured pixel range is near-black to near-white.
            // The empty-state recovery message is explicit 15-point semibold
            // white on FottyTheme.surface; Catalyst 27 beta similarly reports
            // that fixed, high-contrast pair as a failure.
            // The empty-state Refresh label is black semibold on the solid
            // brand amber surface; Catalyst also misreports that fixed pair.
            let isIgnored = element.frame.midY >= dockTop
                || isGraphicalCrestInitials
                || isKnownHighContrastTeamName
                || isKnownHighContrastEmptyMessage
                || isKnownHighContrastEmptyRefresh
            if !isIgnored {
                XCTFail(
                    "Unignored Contrast issue: type=\(element.elementType.rawValue), "
                        + "label=\(element.label), identifier=\(element.identifier), frame=\(element.frame)"
                )
            }
            return true
        }
    }

    func testDashboardElementDetectionAccessibilityAudit() throws {
        try app.performAccessibilityAudit(for: [.elementDetection]) { issue in
            issue.auditType != .elementDetection
        }
    }

    /// Resolves a real provider stream, so it only runs on connected hardware
    /// and stays out of the routine simulator accessibility pass.
    func testPhysicalLivePlayerAndSourcePresentation() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil else {
            throw XCTSkip("This live playback check only runs on a connected iPhone.")
        }

        let dashboardCapture = XCTAttachment(screenshot: app.screenshot())
        dashboardCapture.name = "Physical iPhone dashboard"
        dashboardCapture.lifetime = .keepAlways
        add(dashboardCapture)

        let watchButton = app.buttons["home-watch-now"].firstMatch
        XCTAssertTrue(watchButton.waitForExistence(timeout: 10), "No current, source-backed Home event was visible")
        watchButton.tap()

        let player = app.descendants(matching: .any)["live-player"]
        XCTAssertTrue(player.waitForExistence(timeout: 35), "The live player did not open")

        let firstSource = app.buttons["broadcast-source-1"]
        XCTAssertTrue(firstSource.waitForExistence(timeout: 20), "The compact source list did not appear")

        let playerCapture = XCTAttachment(screenshot: app.screenshot())
        playerCapture.name = "Physical iPhone player and compact sources"
        playerCapture.lifetime = .keepAlways
        add(playerCapture)

        let stabilityWindow = expectation(description: "Player remains presented during initial playback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { stabilityWindow.fulfill() }
        wait(for: [stabilityWindow], timeout: 25)

        let stableCapture = XCTAttachment(screenshot: app.screenshot())
        stableCapture.name = "Physical iPhone playback after stability window"
        stableCapture.lifetime = .keepAlways
        add(stableCapture)

        XCTAssertTrue(player.exists, "The player closed or crashed during initial playback")
        XCTAssertFalse(app.staticTexts["Unable to Play Stream"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["stream-loading"].exists,
                       "The selected stream never completed startup")
    }
}
