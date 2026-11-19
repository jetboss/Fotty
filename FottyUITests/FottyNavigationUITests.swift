import XCTest

final class FottyNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let isAppwidePolishAudit = name.contains("testAppwidePolishVisualJourneys")
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
        case let value where value.contains("testMatchdayDynamicTypeAccessibilityAudit"):
            initialTab = "Arena"
        case let value where value.contains("testSettings") || value.contains("testBetaSupport"):
            initialTab = "Settings"
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
        let isPhysicalLiveTest = name.contains("testPhysicalLivePlayerAndSourcePresentation")
            && ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil
        if isPhysicalLiveTest {
            app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        } else {
            app.launchEnvironment["FOTTY_AUTOMATED_TESTING"] = "1"
        }
        if name.contains("testCricketDiscovery") {
            app.launchEnvironment["FOTTY_CRICKET_UI_TESTING"] = "1"
        }
        if isAppwidePolishAudit || name.contains("testHomeDiscovery") || name.contains("testHomeSportSelection") || name.contains("testDashboard") {
            app.launchEnvironment["FOTTY_HOME_UI_TESTING"] = "1"
        }
        if name.contains("testHomeDiscoveryFootballScoreAndClock") {
            // A fixed historical receipt also catches accidental use of the
            // current clock when classifying or rendering the replay.
            let now = Date(timeIntervalSince1970: 1_798_000_000)
            let observed = now.ISO8601Format()
            let snapshot = """
            {"schemaVersion":1,"complete":true,"checkedAt":"\(observed)","revision":"home-score-test","sourceStatus":"verified",
             "coverage":[{"sport":"football","competitionId":"concacaf-nations-league","competitionName":"Concacaf Nations League",
                          "status":"covered","checkedAt":"\(observed)","fixtureCount":1,"pendingFixtureCount":0}],
             "fixtures":[{"id":"sports-fixture:concacaf-nations-league:test-score","sport":"football","eventKind":"match","status":"live",
                          "start":"\(now.addingTimeInterval(-65 * 60).ISO8601Format())","title":"Curaçao vs Panama",
                          "competitionId":"concacaf-nations-league","competitionName":"Concacaf Nations League",
                          "participants":[{"id":"home","name":"Curaçao","role":"home"},{"id":"away","name":"Panama","role":"away"}],
                          "squad":{"gender":"men","ageGroup":"senior"},"footballLive":{"home":0,"away":0,"clock":"62′"},
                          "source":{"name":"ESPN","url":"https://site.api.espn.com/apis/site/v2/sports/soccer/concacaf.nations.league/scoreboard",
                                    "observedAt":"\(observed)","verification":"verified"}}]}
            """
            app.launchEnvironment["FOTTY_HOME_FOOTBALL_SNAPSHOT_B64"] = Data(snapshot.utf8).base64EncodedString()
            app.launchEnvironment["FOTTY_HOME_REPLAY_AT_RECEIPT"] = "1"
            app.launchArguments += ["-fotty.home.onlyShowSelectedInterests", "NO"]
        }
        if name.contains("testHomeDiscoveryKickoffTransition") {
            app.launchEnvironment["FOTTY_HOME_CLOCK_UI_TESTING"] = "1"
        }
        if name.contains("testDashboardStaleCPL") {
            app.launchEnvironment["FOTTY_CATALOG_UI_STATE"] = "stale-cpl"
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
        case "Settings": initialTabID = "tab-home"
        default: initialTabID = "tab-home"
        }
        let initialTabButton = app.buttons[initialTabID]
        XCTAssertTrue(initialTabButton.waitForExistence(timeout: 12))
        if initialTab == "Home" {
            // Dashboard audits must not inherit whichever tab a previous manual or
            // automated session persisted.
            tapBetaControl(initialTabButton)
        }
        // Settings is a sheet opened from Home's gear, not a tab.
        if initialTab == "Settings" { openSettingsFromHome() }
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground {
            captureSurface("End of \(name)")
        }
        app?.terminate()
    }

    private func captureSurface(_ title: String) {
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = title
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    /// Current-build native renders and real navigation. Fixtures are explicitly
    /// automated; Catalyst window evidence must not be called iPhone acceptance.
    func testWatchFirstDestinationsExcludeRetiredFeatures() throws {
        XCTAssertTrue(app.buttons["tab-home"].exists)
        XCTAssertTrue(app.buttons["tab-tv"].exists)
        XCTAssertTrue(app.buttons["tab-arena"].exists)
        XCTAssertFalse(app.buttons["tab-fpl"].exists)
        XCTAssertFalse(app.buttons["home-watch-two"].exists)
        openSettingsFromHome()
        XCTAssertFalse(app.buttons["Manage in FPL"].exists)
        captureSurface("Watch-first destinations")
    }

    func testAppwidePolishVisualJourneys() throws {
        let launchArguments = app.launchArguments
        for appearance in ["dark", "light"] {
            app.terminate()
            app.launchArguments = launchArguments + ["-fotty.appearance", appearance]
            app.launch()
            XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 12))
            tapBetaControl(app.buttons["tab-home"])
            let football = app.buttons["home-sport-football"]
            XCTAssertTrue(football.waitForExistence(timeout: 8))
            tapBetaControl(football)
            XCTAssertTrue(football.isSelected)
            captureSurface("\(appearance)-Home-football-sample")
            tapBetaControl(app.buttons["home-sport-all-sports"])

            tapBetaControl(app.buttons["home-search"])
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            tapBetaControl(search)
            search.typeText("cricket")
            XCTAssertTrue(app.descendants(matching: .any)["search-result-cpl-2026-ui-home"].firstMatch.waitForExistence(timeout: 5))
            captureSurface("\(appearance)-Search-cricket-sample")
            tapBetaControl(app.buttons["Done"].firstMatch)

            tapBetaControl(app.buttons["tab-arena"])
            captureSurface("\(appearance)-Matchday-sample")
            openSettingsFromHome()
            let appearanceRow = app.buttons["settings-appearance"]
            reveal(appearanceRow)
            captureSurface("\(appearance)-Settings")
            tapBetaControl(appearanceRow)
            XCTAssertTrue(app.buttons["appearance-system"].waitForExistence(timeout: 5))
            captureSurface("\(appearance)-Appearance")
            tapBetaControl(app.navigationBars.buttons.firstMatch)

            tapBetaControl(app.buttons["tab-home"])
            XCTAssertTrue(app.buttons["home-sport-all-sports"].waitForExistence(timeout: 5))
        }
    }

    func testHomeDiscoveryFootballScoreAndClock() throws {
        let hero = app.buttons["home-live-details-sports-fixture:concacaf-nations-league:test-score"]
        XCTAssertTrue(hero.waitForExistence(timeout: 12), "The official live fixture never appeared in the Home hero")
        XCTAssertTrue(hero.label.contains("0 – 0"), "Missing score in the Home hero: \(hero.label)")
        XCTAssertTrue(hero.label.contains("62′"), "Missing publisher match minute in the Home hero: \(hero.label)")
    }

    func testHomeDiscoveryKickoffTransition() throws {
        #if targetEnvironment(macCatalyst)
        let window = app.windows.firstMatch
        let originalSize = window.frame.size
        func resize(_ size: CGSize) {
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -3, dy: -3))
            let destination = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: size.width - 3, dy: size.height - 3))
            corner.click(forDuration: 0.2, thenDragTo: destination)
        }
        defer { resize(originalSize) }
        resize(CGSize(width: 1180, height: 950))
        XCTAssertGreaterThan(window.frame.width, 1000)
        // Home rows carry their countdown in the row's own secondary line.
        let today = rowStatusElement("cpl-2026-ui-today")
        let next = rowStatusElement("cpl-2026-ui-next")
        reveal(today)
        XCTAssertTrue(today.label.contains("1h 5m"))
        XCTAssertEqual(today.frame.minY, next.frame.minY, accuracy: 12)
        let advance = app.buttons["home-test-advance-clock"]
        reveal(advance)
        tapBetaControl(advance)
        // Catalyst's iPad idiom scales UIKit points relative to AppKit window
        // points. Use a window comfortably below the 1,000 UIKit-point boundary.
        resize(CGSize(width: 600, height: 950))
        XCTAssertLessThan(window.frame.width, 1000)
        let live = app.staticTexts["home-live-heading"]
        reveal(live)
        XCTAssertTrue(live.exists)
        let currentReady = today.wait(for: \.label, toEqual: "No stream listed", timeout: 5)
        let transitionImage = XCTAttachment(screenshot: app.screenshot())
        transitionImage.name = "Home-after-kickoff-and-resize"
        transitionImage.lifetime = .keepAlways
        add(transitionImage)
        XCTAssertTrue(currentReady, "A past kickoff must not keep the old countdown: \(today.label)")
        XCTAssertGreaterThan(today.frame.maxX, window.frame.maxX - 80,
                             "A narrow window must not retain a half-width landscape card")
        reveal(next)
        XCTAssertTrue(next.label.contains("25m"), "The surviving upcoming row must use the current clock: \(next.label)")
        let nextCopies = max(app.staticTexts.matching(identifier: "match-start-countdown-cpl-2026-ui-next").count,
                             app.descendants(matching: .any).matching(identifier: "home-event-cpl-2026-ui-next").count)
        XCTAssertEqual(nextCopies, 1, "An upcoming card cannot remain duplicated under Live now")
        XCTAssertGreaterThan(next.frame.minY, today.frame.minY)
        openSettingsFromHome()
        tapBetaControl(app.buttons["tab-home"])
        app.activate()
        reveal(next)
        XCTAssertEqual(today.label, "No stream listed")
        XCTAssertTrue(next.label.contains("25m"))
        #else
        throw XCTSkip("This transition journey uses native Catalyst resizing; no simulator required")
        #endif
    }

    func testHomeDiscoveryShowsActivityFiltersAndFullLineup() throws {
        XCTAssertFalse(app.descendants(matching: .any)["catalog-refresh-notice"].firstMatch.exists,
                       "Verified listings should show no routine status banner")
        XCTAssertEqual(app.buttons["tab-home"].label, "Home")
        XCTAssertTrue(app.buttons["home-sport-football"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Field Events"].exists)
        XCTAssertFalse(app.staticTexts["Reference"].exists)
        let all = app.buttons["home-sport-all-sports"]
        XCTAssertTrue(all.waitForExistence(timeout: 8))
        XCTAssertTrue(all.isSelected)
        XCTAssertEqual(app.buttons["home-sport-basketball"].value as? String, "1 on now")
        XCTAssertTrue(app.staticTexts["home-live-heading"].exists, "Current broadcasts must have a visible Live now section")
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
        XCTAssertTrue(rowStatusElement("ui-rugby").exists)
        XCTAssertFalse(app.buttons["match-start-play-ui-rugby"].exists, "A future source-free row must not open an empty player")
        tapBetaControl(app.buttons["tab-arena"])
        XCTAssertTrue(app.staticTexts["Trinbago Knight Riders"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your squad in action"].exists)
        captureSurface("Matchday-saved-cricket-sample")
        openMatchMenu(app.staticTexts["Trinbago Knight Riders"].firstMatch)
        selectMatchMenuAction("Remove from My Matchday")
        XCTAssertFalse(app.staticTexts["Trinbago Knight Riders"].exists)
    }

    func testDashboardStaleCPLNoticeIsScopedAndDetailsAreOptional() throws {
        let warning = app.staticTexts["CPL start times may have changed."]
        XCTAssertTrue(warning.waitForExistence(timeout: 8))
        let checkTime = app.staticTexts["catalog-check-time"]
        XCTAssertFalse(checkTime.exists, "Check times should be hidden until requested")
        let details = app.buttons["catalog-update-details"]
        XCTAssertTrue(details.exists, "Update details must remain an independently accessible control")
        reveal(details)
        tapBetaControl(details)
        XCTAssertTrue(checkTime.waitForExistence(timeout: 3))
        tapBetaControl(details)
        XCTAssertFalse(checkTime.exists)
        let football = app.buttons["home-sport-football"]
        reveal(football)
        tapBetaControl(football)
        XCTAssertFalse(warning.exists, "CPL freshness must not interrupt a football-only screen")
        XCTAssertTrue(app.buttons["match-start-play-ui-football"].exists)
    }

    func testDashboardPartialCatalogTelemetryStaysOffCustomerUI() throws {
        XCTAssertFalse(app.staticTexts["Some broadcasts may be missing."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["catalog-refresh-notice"].exists)
        XCTAssertTrue(app.buttons["match-start-play-ui-football"].exists)
    }

    func testDashboardSportFilterNamesItsEmptyStateAndCanReturnToAllSports() throws {
        let fight = app.buttons["home-sport-fight"]
        reveal(fight)
        tapBetaControl(fight)
        XCTAssertTrue(app.staticTexts["No Fight events are starting in the next six hours."].waitForExistence(timeout: 5))
        let showAll = app.buttons["home-show-all-sports"]
        XCTAssertTrue(showAll.exists)
        tapBetaControl(showAll)
        XCTAssertTrue(app.buttons["match-start-play-ui-football"].waitForExistence(timeout: 5))
    }

    func testSettingsKickoffClashesRemainOptionalAcrossNavigation() throws {
        let toggle = app.switches["Show kickoff clashes"]
        reveal(toggle)
        let originalValue = try XCTUnwrap(toggle.value as? String)
        defer {
            openSettingsFromHome()
            reveal(toggle)
            if toggle.value as? String != originalValue { tapBetaControl(toggle) }
        }

        if originalValue == "1" { tapBetaControl(toggle) }
        XCTAssertEqual(toggle.value as? String, "0")
        tapBetaControl(app.buttons["tab-arena"])
        XCTAssertFalse(app.descendants(matching: .any)["matchday-clash-details"].exists)
        openSettingsFromHome()
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        tapBetaControl(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        tapBetaControl(app.buttons["tab-arena"])
        openSettingsFromHome()
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "The opt-in should survive leaving Settings")
    }

    func testSettingsNotificationPreferencesAreGrouped() throws {
        let notifications = app.buttons["settings-notifications"]
        reveal(notifications)
        XCTAssertFalse(app.switches["Kickoff Updates"].exists)
        XCTAssertTrue(app.buttons["settings-interests"].exists)
        tapBetaControl(notifications)
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        let kickoff = app.switches["Kickoff Updates"]
        reveal(kickoff)
        XCTAssertTrue(kickoff.exists)
        XCTAssertTrue(app.switches["Goal Updates"].exists)
        XCTAssertTrue(app.switches["Full-time Updates"].exists)
        tapBetaControl(app.navigationBars.buttons.firstMatch)
        let backup = app.buttons["settings-backup"]
        reveal(backup)
        XCTAssertTrue(backup.exists)
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
        if !element.exists || !element.isHittable {
            print("Unreachable control: exists=\(element.exists), window=\(app.windows.firstMatch.frame)")
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.name = "Unreachable-control-layout"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected a reachable control: \(element)")
    }

    private func activateBetaWindow() -> Bool {
        app.activate()
        let ready = app.wait(for: .runningForeground, timeout: 5)
        XCTAssertTrue(ready, "Fotty must stay in the foreground for UI interaction checks")
        return ready
    }

    /// Settings opens as a sheet from Home's gear button.
    private func openSettingsFromHome() {
        guard !app.buttons["settings-done"].exists else { return }
        let home = app.buttons["tab-home"]
        if home.exists { tapBetaControl(home) }
        let gear = app.buttons["home-settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "Home's Settings gear is missing")
        tapBetaControl(gear)
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5), "Settings sheet did not open")
    }

    private func tapBetaControl(_ element: XCUIElement) {
        // A tab is behind an open Settings sheet; close it first, as a person
        // would: Back out of any page pushed inside Settings, then Done.
        if element.identifier.hasPrefix("tab-"), !element.isHittable {
            let done = app.buttons["settings-done"]
            if !done.exists, let back = app.navigationBars.buttons.allElementsBoundByIndex.first(where: \.isHittable) {
                back.tap()
            }
            if done.waitForExistence(timeout: 3) { done.tap() }
        }
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
        let tabIDs = ["tab-arena", "tab-tv", "tab-home"]

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

    func testHomeSportSelectionSurvivesTabSwitch() {
        let cricket = app.buttons["home-sport-cricket"]
        reveal(cricket)
        tapBetaControl(cricket)
        XCTAssertTrue(cricket.wait(for: \.isSelected, toEqual: true, timeout: 3))

        openSettingsFromHome()
        tapBetaControl(app.buttons["tab-home"])

        let restoredCricket = app.buttons["home-sport-cricket"]
        reveal(restoredCricket)
        XCTAssertTrue(
            restoredCricket.wait(for: \.isSelected, toEqual: true, timeout: 3),
            "Returning Home must preserve the selected sport"
        )
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
        try performSurfaceDynamicTypeAudit(surface: "Home", dockTop: app.buttons["tab-home"].frame.minY)
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
            dockTop: app.buttons["tab-home"].frame.minY
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
            let isIgnored = FottyAccessibilityAuditPolicy.ignoresDynamicType(
                identifier: element.identifier, label: text, isStaticText: true,
                frame: element.frame, isCatalyst: self.auditIsCatalyst,
                osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            )
            if !isIgnored {
                self.captureSurface("\(surface)-dynamic-type-failure")
                print(
                    "Unignored \(surface) Dynamic Type issue: "
                        + "type=\(element.elementType.rawValue), label=\(text), "
                        + "identifier=\(element.identifier), frame=\(element.frame)"
                )
            }
            return isIgnored
        }
    }

    private var auditIsCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    func testDashboardContrastAndTraitsAccessibilityAudit() throws {
        try app.performAccessibilityAudit(for: [.contrast, .trait]) { issue in
            guard issue.auditType == .contrast || issue.auditType == .trait else {
                return false
            }
            if issue.auditType == .trait {
                self.captureSurface("dashboard-trait-failure")
                if let element = issue.element {
                    XCTFail(
                        "Unignored Trait issue: type=\(element.elementType.rawValue), "
                            + "label=\(element.label), identifier=\(element.identifier), frame=\(element.frame)"
                    )
                    return true // XCTFail above records the inspected issue.
                }
                return false // Unresolved elements still fail XCTest's audit.
            }
            guard let element = issue.element,
                  element.elementType == .staticText else { return false }
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let isIgnored = FottyAccessibilityAuditPolicy.ignoresContrast(
                identifier: element.identifier, label: label, isStaticText: true,
                frame: element.frame, isCatalyst: self.auditIsCatalyst,
                osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            )
            if !isIgnored {
                let screenshot = XCTAttachment(screenshot: self.app.screenshot())
                screenshot.name = "Dashboard contrast failure"
                screenshot.lifetime = .keepAlways
                self.add(screenshot)
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

        // A provider embed can remain active beneath Fotty's toolbar. Verify the
        // visible control itself receives the tap rather than passing it through
        // to the underlying web player. Native handoff sources use native chrome
        // and therefore do not expose this web-only button.
        let webTransport = app.buttons["web-play-pause"]
        if webTransport.waitForExistence(timeout: 3) {
            XCTAssertTrue(webTransport.label.localizedCaseInsensitiveContains("Pause"))
            webTransport.tap()
            let becamePlay = NSPredicate(format: "label CONTAINS[c] %@", "Play")
            expectation(for: becamePlay, evaluatedWith: webTransport)
            waitForExpectations(timeout: 3)

            webTransport.tap()
            let becamePause = NSPredicate(format: "label CONTAINS[c] %@", "Pause")
            expectation(for: becamePause, evaluatedWith: webTransport)
            waitForExpectations(timeout: 3)
        }
    }

}

/// Normal owner-device data and real navigation, deliberately independent of
/// the fixture setup above. Static UI readiness is not media qualification.
final class Fotty25PhysicalUIJourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPhysicalSearchSportTileSurfacesHaveEqualHeight() throws {
        let app = try launchNormalHome()
        defer { app.terminate() }
        let searchButton = app.buttons["home-search"].firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 20)); searchButton.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let previous = field.value as? String
        let query = previous == field.placeholderValue ? nil : previous
        if let query, !query.isEmpty {
            field.tap()
            let clear = field.buttons["Clear text"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 3)); clear.tap()
            // Leave native search-completion mode before measuring the prompt
            // behind it. An untouched empty field needs no focus/keyboard.
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 2), cancel.isHittable { cancel.tap() }
        }
        defer {
            if let query, !query.isEmpty, field.exists {
                field.tap(); field.typeText(query)
            }
            let done = app.buttons["Done"].firstMatch
            if done.exists && done.isHittable { done.tap() }
        }
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-sport-"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 8))
        for _ in 0..<3 {
            if tiles.allElementsBoundByIndex.filter(\.isHittable).count >= 2 { break }
            app.swipeUp()
        }
        var seen = Set<String>()
        let rendered = tiles.allElementsBoundByIndex.filter {
            $0.isHittable && app.frame.intersects($0.frame) && seen.insert($0.identifier).inserted
        }
        XCTAssertGreaterThanOrEqual(rendered.count, 2, "Compare visible, tappable sport surfaces, not offscreen AX frames")
        let height = try XCTUnwrap(rendered.first).frame.height
        XCTAssertGreaterThanOrEqual(height, 76)
        for tile in rendered {
            XCTAssertEqual(tile.frame.height, height, accuracy: 1, tile.identifier)
        }
        captureDisplay("physical-Search-equal-sport-surfaces")
    }

    func testPhysicalCatalogDetailsWithoutSavingOrStartingPlayback() throws {
        let app = try launchNormalHome()
        defer { app.terminate() }
        // Rows show one action; Details lives in the row's long-press menu.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-event-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.press(forDuration: 1.0)
        let details = app.buttons["Match details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 4)); details.tap()
        let close = app.buttons["Close"].firstMatch
        if !close.waitForExistence(timeout: 2) {
            let expandedDetails = app.buttons["More details"].firstMatch
            XCTAssertTrue(expandedDetails.waitForExistence(timeout: 3))
            for _ in 0..<4 {
                if expandedDetails.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(expandedDetails.isHittable); expandedDetails.tap()
        }
        captureDisplay("physical-CatalogDetails-entry-state")
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["match-details-save"].firstMatch.exists)
        captureDisplay("physical-CatalogEventDetails-read-only")
        close.tap()
        XCTAssertTrue(app.buttons["home-search"].firstMatch.waitForExistence(timeout: 5))
    }

    func testPhysicalLandscapeCoreLayoutWithoutChangingPreferences() throws {
        let app = try launchNormalHome()
        let previousOrientation = XCUIDevice.shared.orientation
        defer {
            XCUIDevice.shared.orientation = previousOrientation
            app.terminate()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed,
                       "The approved iPad layout must adapt to its landscape viewport")
        let search = app.buttons["home-search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        assertVisible(search, in: app, minimumHeight: 44)
        captureDisplay("physical-Home-landscape-display")
        app.buttons["tab-arena"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["matchday-view-mode"].firstMatch.waitForExistence(timeout: 5))
        captureDisplay("physical-Matchday-landscape-display")
        app.buttons["tab-home"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home-settings"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["home-settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 5))
        captureDisplay("physical-Settings-landscape-display")
        let displayObservation = expectation(description: "Bounded physical display observation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { displayObservation.fulfill() }
        wait(for: [displayObservation], timeout: 18)
        app.buttons["tab-home"].firstMatch.tap()
    }

    func testPhysicalCoreNavigationWithoutChangingPreferences() throws {
        let app = try launchNormalHome()
        defer { app.terminate() }
        let searchButton = app.buttons["home-search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 20))
        assertVisible(searchButton, in: app, minimumHeight: 44)
        capture(app, "physical-Home-normal-catalog")
        searchButton.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        // A normal owner scene can restore a query. Do not append to it or
        // pretend restoration is a defect; preserve it without submitting.
        let restoredValue = search.value as? String
        let restoredQuery = restoredValue == search.placeholderValue ? nil : restoredValue
        search.tap()
        let clearQuery = search.buttons["Clear text"].firstMatch
        if clearQuery.exists { clearQuery.tap() }
        search.tap()
        search.typeText("cricket") // Do not submit or write recent searches.
        XCTAssertEqual(search.value as? String, "cricket")
        capture(app, "physical-Search-typed-query-keyboard")
        XCTAssertTrue(clearQuery.isHittable)
        clearQuery.tap()
        if let restoredQuery, !restoredQuery.isEmpty {
            search.tap(); search.typeText(restoredQuery)
        }
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.isHittable, "Search dismissal must remain usable with the keyboard open")
        done.tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        app.buttons["tab-home"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home-settings"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["home-settings"].firstMatch.tap()
        let appearance = app.buttons["settings-appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        capture(app, "physical-Settings-normal-preferences")
        appearance.tap()
        XCTAssertTrue(app.buttons["appearance-system"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance-light"].exists)
        XCTAssertTrue(app.buttons["appearance-dark"].exists)
        capture(app, "physical-Appearance-read-only")
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable); back.tap()
        app.buttons["tab-arena"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["matchday-view-mode"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "physical-Matchday-normal-saved-data")
        app.buttons["tab-home"].firstMatch.tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        assertVisible(searchButton, in: app, minimumHeight: 44)
        capture(app, "physical-Home-returned")
    }

    /// Visual review of the black-stage player: ready, info open, chrome dimmed.
    func testPhysicalPlayerStageCaptures() throws {
        let app = try launchNormalHome()
        defer { app.terminate() }
        let watches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS[c] %@)", "Watch", "two"))
        _ = watches.firstMatch.waitForExistence(timeout: 30)
        sleep(3)
        let player = app.descendants(matching: .any)["viewing-experience"].firstMatch
        var opened = false
        // Try listed Watch actions in order; a fixture with no stream shows
        // an alert, which is dismissed before the next one is tried.
        for watch in watches.allElementsBoundByIndex.filter({ $0.isHittable && $0.isEnabled }).prefix(6) {
            watch.tap()
            if player.waitForExistence(timeout: 30) { opened = true; break }
            let ok = app.alerts.buttons["OK"].firstMatch
            if ok.exists { ok.tap(); sleep(1) }
        }
        guard opened else { capture(app, "stage-no-player"); throw XCTSkip("No listed Watch opened the player.") }
        let close = app.buttons["close-live-player"].firstMatch
        defer { if close.exists && close.isHittable { close.tap() } }
        _ = app.buttons["viewing-native-fullscreen"].firstMatch.waitForExistence(timeout: 20)
        sleep(2)
        captureDisplay("stage-ready")
        let details = app.buttons["viewing-details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(details.frame.height, 44)
        details.tap(); sleep(2)
        captureDisplay("stage-info-open")
        let done = app.buttons["viewing-details-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        sleep(7)
        captureDisplay("stage-chrome-dimmed")
        let sources = app.buttons["viewing-sources"].firstMatch
        XCTAssertTrue(sources.exists && sources.isHittable, "Sources stays reachable")
    }

    func testPhysicalSinglePlayerSourceAndDetailsPresentation() throws {
        let app = try launchNormalHome()
        defer { app.terminate() }
        let watches = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND (label BEGINSWITH %@ OR label BEGINSWITH %@)",
            "match-start-play-", "Watch ", "Retry "))
        let watch = watches.firstMatch
        guard watch.waitForExistence(timeout: 20), watch.isHittable, watch.isEnabled else {
            capture(app, "physical-player-gate-no-visible-listed-Watch")
            throw XCTSkip("No visible currently eligible listed-match Watch action; no source/player pass claimed.")
        }
        watch.tap()
        let player = app.descendants(matching: .any)["viewing-experience"].firstMatch
        guard player.waitForExistence(timeout: 25) else {
            capture(app, "physical-player-gate-current-delivery-unavailable")
            throw XCTSkip("The current provider delivery did not open the normal player within25seconds.")
        }
        let close = app.buttons["close-live-player"].firstMatch
        defer { if close.exists && close.isHittable { close.tap() } }
        let fullscreen = app.buttons["viewing-native-fullscreen"].firstMatch
        let webTransport = app.buttons["web-play-pause"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (fullscreen.exists && fullscreen.isEnabled)
                || (webTransport.exists && webTransport.isEnabled && webTransport.label.localizedCaseInsensitiveContains("Pause"))
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 25) == .completed else {
            capture(app, "physical-player-gate-not-ready-no-media-pass")
            throw XCTSkip("The current delivery never exposed native-ready or playing-web controls; UI playback gate remains unverified.")
        }
        let sources = app.buttons["viewing-sources"].firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        assertVisible(sources, in: app, minimumHeight: 44)
        let selectedSource = sources.value as? String
        capture(app, "physical-single-player-ready-UI-not-frame-qualification")
        sources.tap()
        XCTAssertTrue(app.descendants(matching: .any)["single-source-picker-scroll"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "physical-single-player-Sources-no-selection")
        let list = app.scrollViews["single-source-picker-scroll"].firstMatch
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "broadcast-source-"))
        if let last = rows.allElementsBoundByIndex.last {
            for _ in 0..<4 {
                if last.isHittable { break }
                list.swipeUp()
            }
            XCTAssertTrue(last.isHittable, "The last current source must be reachable in the sheet")
        }
        XCTAssertTrue(app.buttons["Close broadcast sources"].isHittable)
        capture(app, "physical-single-player-Sources-bottom-pinned-Close")
        app.buttons["Close broadcast sources"].tap()
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        XCTAssertEqual(sources.value as? String, selectedSource, "Opening/closing Sources must not select another delivery")
        XCTAssertTrue(player.exists)
        let details = app.buttons["viewing-details"].firstMatch
        XCTAssertTrue(details.isHittable); details.tap()
        let detailsDone = app.buttons["viewing-details-done"]
        XCTAssertTrue(detailsDone.waitForExistence(timeout: 5))
        capture(app, "physical-single-player-Details")
        detailsDone.tap()
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        if fullscreen.exists && fullscreen.isEnabled {
            assertVisible(fullscreen, in: app, minimumHeight: 44)
            capture(app, "physical-native-fullscreen-affordance-eligible-not-transition-proof")
        }
    }

    private func launchNormalHome() throws -> XCUIApplication {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        throw XCTSkip("This journey requires the approved physical Jet iPad.")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-fotty.onboarding.hasDismissed", "YES", "-fotty.selectedTab", "Home", "-fotty.setup.dismissed.v1", "YES"]
        // The existing physical gate bypasses XCTest's automatic fixture/feed
        // suppression, keeps real providers, and mutes only test playback audio.
        app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 12))
        return app
        #endif
    }

    private func assertVisible(_ element: XCUIElement, in app: XCUIApplication, minimumHeight: CGFloat) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.height, minimumHeight - 1)
        XCTAssertGreaterThanOrEqual(element.frame.width, 43)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame), "Control must remain within the actual app viewport")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func captureDisplay(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

extension FottyNavigationUITests {
    /// A row's status: the separate countdown element where a screen still
    /// draws one, otherwise the row itself (Home rows embed the status).
    func rowStatusElement(_ eventID: String) -> XCUIElement {
        let countdown = app.descendants(matching: .any)["match-start-countdown-\(eventID)"].firstMatch
        return countdown.exists ? countdown : app.descendants(matching: .any)["home-event-\(eventID)"].firstMatch
    }
}
