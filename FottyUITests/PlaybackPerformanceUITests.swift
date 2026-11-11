import XCTest
import UIKit
import AVFoundation

/// Production-feed checks on owner hardware. These do not inject catalog/FPL
/// fixtures, clear persistence, or change source configuration. UI timings
/// include XCTest overhead and are not frame-rate or Instruments measurements.
final class PlaybackPerformanceUITests: XCTestCase {
    private var app: XCUIApplication!
    private var endSurface = "Home"
    private var navigationTimings: [String] = []
    private var capturedFocusedEnd = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("These checks require physical iOS/iPadOS hardware.")
        #else
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil else {
            throw XCTSkip("These checks do not run on simulators.")
        }
        app = XCUIApplication()
        app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        app.launchArguments = [
            "-fotty.onboarding.hasDismissed", "YES",
            "-fotty.setup.dismissed.v1", "YES"
        ]
        app.launch()
        XCTAssertTrue(tabControl("tab-home").waitForExistence(timeout: 15))
        tap(tabControl("tab-home"))
        #endif
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground, !capturedFocusedEnd {
            captureEvidence(surface: endSurface)
        }
        if !navigationTimings.isEmpty {
            let timing = XCTAttachment(string: navigationTimings.joined(separator: "\n"))
            timing.name = "UI command-to-state timing (not frame-rate evidence)"
            timing.lifetime = .keepAlways
            add(timing)
        }
        app?.terminate()
    }

    func testBroadcastFirstHomeAndTVJourney() throws {
        XCTAssertTrue(app.staticTexts["home-context-heading"].waitForExistence(timeout: 20))
        captureEvidence(surface: "3.0 broadcast-first Home")
        let follow = app.buttons["home-follow-club"].firstMatch
        if follow.exists && follow.isHittable {
            follow.tap()
            XCTAssertTrue(app.textFields["follow-team-search"].firstMatch.waitForExistence(timeout: 8))
            captureEvidence(surface: "3.0 optional club picker")
            let done = app.buttons["Done"].firstMatch
            if done.exists && done.isHittable { done.tap() }
            else { app.swipeDown() }
        }
        try selectTab("tab-tv", surface: "3.0 Sports TV")
        let filter = app.segmentedControls["sports-tv-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.buttons["English"].tap()
        captureEvidence(surface: "3.0 English channels")
        filter.buttons["Favourites"].tap()
        captureEvidence(surface: "3.0 Favourite channels")
        filter.buttons["All channels"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5) && search.isHittable)
        search.tap(); search.typeText("Willow")
        XCTAssertTrue(app.staticTexts["Willow Cricket"].firstMatch.waitForExistence(timeout: 8))
        captureEvidence(surface: "3.0 channel search")
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No matching channels"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["sports-tv-reset"].firstMatch.tap()
        captureEvidence(surface: "3.0 channel search reset")
        capturedFocusedEnd = true
    }

    func testTailoredHomeOnJet() {
        let heading = app.staticTexts["home-context-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20))
        XCTAssertEqual(heading.label, "Tailored to you")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tailored Home on Jet"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["home-selected-scope"].firstMatch.tap()
        let follow = app.buttons["Follow a club"].firstMatch
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        follow.tap()
        XCTAssertTrue(app.textFields["follow-team-search"].firstMatch.waitForExistence(timeout: 8))
    }

    /// Capture the real Home composition without persisting an appearance
    /// preference. Decorations need native visual review, not an AX-only pass.
    func testPhysicalProductionHomeMatchSeparationInBothAppearances() throws {
        for appearance in ["light", "dark"] {
            app.terminate()
            app.launchArguments = [
                "-fotty.onboarding.hasDismissed", "YES",
                "-fotty.setup.dismissed.v1", "YES",
                "-fotty.appearance", appearance
            ]
            app.launch()
            XCTAssertTrue(tabControl("tab-home").waitForExistence(timeout: 15))
            tap(tabControl("tab-home"))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home-discovery-heading")
                .firstMatch.waitForExistence(timeout: 20), "Real Home fixtures must load before visual comparison")
            captureEvidence(surface: "Production Home match boundaries \(appearance) top")
            let scroll = visibleContentScroll
            XCTAssertTrue(scroll.exists && scroll.isHittable)
            scroll.swipeUp()
            XCTAssertEqual(app.state, .runningForeground)
            captureEvidence(surface: "Production Home match boundaries \(appearance) scrolled")
        }
        capturedFocusedEnd = true
        endSurface = "Home match boundaries in both appearances; visual review required"
    }

    /// Inspect the real anchored plan without changing saved durations/follows
    /// or inventing fixtures. Full Matchday must remain a distinct destination.
    func testPhysicalTonightAndFullMatchdayRemainDistinct() throws {
        try selectTab("tab-arena", surface: "Personal Full Matchday schedule")
        let mode = app.segmentedControls["matchday-view-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        let duration = app.descendants(matching: .any)["matchday-viewing-duration"].firstMatch
        XCTAssertTrue(mode.buttons["Full Matchday"].isSelected,
                      "The personal schedule must open without an implicit time filter")
        XCTAssertFalse(duration.exists)
        tap(mode.buttons["Time window"])
        XCTAssertTrue(duration.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Your viewing window, from"
        )).firstMatch.exists, "Time window must identify its actual anchored interval")
        captureEvidence(surface: "Native optional anchored time window")
        tap(mode.buttons["Full Matchday"])
        XCTAssertTrue(waitUntil(timeout: 5) { !duration.exists })
        XCTAssertEqual(app.state, .runningForeground)
        captureEvidence(surface: "Native Full Matchday distinct from optional time window")
        tap(mode.buttons["Time window"])
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        try selectTab("tab-home", surface: "Home after personal-plan comparison")
        capturedFocusedEnd = true
    }

    /// Real editor persistence, with the owner's original selection restored.
    /// This does not toggle sports-sync consent or alter any team/league/FPL data.
    func testPhysicalWholeSportInterestEditorPersistsAndRestoresSelection() throws {
        guard ProcessInfo.processInfo.environment["FOTTY_ALLOW_TEMPORARY_SPORT_PREFERENCES"] == "1" else {
            throw XCTSkip("A temporary whole-sport edit requires the named owner-device gate flag.")
        }
        try openHomeInterestEditor()
        let cricket = app.buttons["interest-sport-cricket"]
        try reveal(cricket)
        let original = try XCTUnwrap(cricket.value as? String)
        XCTAssertTrue(["Following", "Not followed"].contains(original))
        let onlySelected = app.switches["interest-only-selected"]
        try reveal(onlySelected)
        let originalScope = try XCTUnwrap(onlySelected.value as? String)
        defer {
            try? openHomeInterestEditor()
            if cricket.exists, cricket.value as? String != original {
                try? reveal(cricket)
                if cricket.isHittable { tap(cricket) }
            }
            if onlySelected.exists, onlySelected.value as? String != originalScope {
                try? reveal(onlySelected)
                if onlySelected.isHittable && onlySelected.isEnabled { tap(onlySelected) }
            }
        }
        try reveal(cricket)
        tap(cricket)
        let expected = original == "Following" ? "Not followed" : "Following"
        XCTAssertTrue(waitUntil(timeout: 5) { cricket.value as? String == expected })
        captureEvidence(surface: "Whole-sport interests native selection before returning Home")
        try selectTab("tab-home", surface: "Home with updated whole-sport interest")
        try selectTab("tab-arena", surface: "Full Matchday after whole-sport interest edit")
        XCTAssertTrue(app.segmentedControls["matchday-view-mode"].buttons["Full Matchday"].isSelected)
        try openHomeInterestEditor()
        try reveal(cricket)
        XCTAssertEqual(cricket.value as? String, expected,
                       "The sport choice must survive leaving and returning to the editor")
        tap(cricket)
        XCTAssertTrue(waitUntil(timeout: 5) { cricket.value as? String == original })
        try reveal(onlySelected)
        if onlySelected.value as? String != originalScope { tap(onlySelected) }
        XCTAssertEqual(onlySelected.value as? String, originalScope,
                       "Removing the last interest may disable filtering; restore the owner's original scope too")
        captureEvidence(surface: "Whole-sport interests restored to owner's original choice")
        try selectTab("tab-home", surface: "Home after restored sports preferences")
        capturedFocusedEnd = true
    }

    /// Exercise the ordinary Home menu and details, not a fixture/debug route.
    /// Only an originally unsaved future row is edited: removing a previously
    /// saved match could cancel the owner's reminder, which is out of scope.
    func testPhysicalHomeMoreDetailsSaveAndRemoveRestoresOriginalState() throws {
        try selectTab("tab-home", surface: "Home real match long-press menu")
        // Rows show one action; Details and Save live in the row's long-press
        // menu. The visible "Saved" cue (match-saved-<id>) reports saved state.
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-event-"))
        _ = rows.firstMatch.waitForExistence(timeout: 20)
        var chosenID: String?
        for _ in 0..<6 {
            for row in rows.allElementsBoundByIndex.prefix(12) where row.isHittable {
                let eventID = String(row.identifier.dropFirst("home-event-".count))
                guard !isSavedOnHome(eventID) else { continue }
                let countdown = app.descendants(matching: .any).matching(identifier: "match-start-countdown-\(eventID)").firstMatch
                guard countdown.exists else { continue }
                let label = countdown.label.lowercased()
                // A real scheduled countdown proves a dated fixture, not an
                // undated channel. Avoid a near-kickoff row moving mid-check.
                guard label.hasPrefix("scheduled starts in"),
                      label.range(of: #"\b(?:[1-9][0-9]*[hd]|(?:[5-9]|[1-9][0-9]+)m)"#,
                                  options: .regularExpression) != nil else { continue }
                chosenID = eventID
                break
            }
            if chosenID != nil { break }
            let scroll = visibleContentScroll
            if scroll.exists && scroll.isHittable { scroll.swipeUp() } else { break }
        }
        guard let eventID = chosenID else {
            captureEvidence(surface: "Home More-details gate: no suitable real unsaved future row in six bounded viewports")
            throw XCTSkip("No real unsaved dated fixture at least five minutes away was reachable in the bounded Home scan; existing saved matches and reminders were left untouched.")
        }
        let menu = app.buttons["home-event-\(eventID)"]
        XCTAssertFalse(isSavedOnHome(eventID))
        var mayNeedRestore = false
        defer {
            if mayNeedRestore {
                do { try restoreUnsavedHomeDetailsFixture(eventID: eventID) }
                catch {
                    captureEvidence(surface: "Home save-details original-state restoration failed")
                    XCTFail("Could not verify restoration of the test-created saved fixture: \(eventID)")
                }
            }
        }

        menu.press(forDuration: 1.0)
        let detailsAction = app.buttons["Match details"].firstMatch
        XCTAssertTrue(detailsAction.waitForExistence(timeout: 5), "The row's long-press menu must expose Match details")
        tap(detailsAction)
        let save = app.buttons["match-details-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        try reveal(save)
        XCTAssertEqual(save.label, "Save to My Matchday", "Do not edit an existing saved match or its reminder")
        mayNeedRestore = true // Install cleanup before the first possible write.
        tap(save)
        XCTAssertTrue(waitUntil(timeout: 5) { save.label == "Remove from My Matchday" })
        XCTAssertFalse(app.alerts["Couldn't update My Matchday"].exists)
        captureEvidence(surface: "Real Home More menu match details after explicit Save")
        let close = app.navigationBars["Match details"].buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        tap(close)
        XCTAssertTrue(waitUntil(timeout: 5) { !save.exists && self.isSavedOnHome(eventID) })
        XCTAssertTrue(app.descendants(matching: .any)["match-saved-\(eventID)"].firstMatch.exists,
                      "Home must show the actual saved-state cue after details closes")

        try reveal(menu)
        menu.press(forDuration: 1.0)
        XCTAssertTrue(detailsAction.waitForExistence(timeout: 5))
        tap(detailsAction)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        try reveal(save)
        XCTAssertEqual(save.label, "Remove from My Matchday")
        tap(save)
        XCTAssertTrue(waitUntil(timeout: 5) { save.label == "Save to My Matchday" })
        XCTAssertFalse(app.alerts["Couldn't update My Matchday"].exists)
        tap(close)
        XCTAssertTrue(waitUntil(timeout: 5) { !save.exists && !self.isSavedOnHome(eventID) })
        XCTAssertFalse(app.descendants(matching: .any)["match-saved-\(eventID)"].firstMatch.exists)
        mayNeedRestore = false
        XCTAssertTrue(tabControl("tab-home").isSelected)
        XCTAssertEqual(app.state, .runningForeground)
        captureEvidence(surface: "Home after real details Save and Remove; original unsaved state restored")
        endSurface = "Home after reversible real match More-details save check"
        capturedFocusedEnd = true
    }

    private func restoreUnsavedHomeDetailsFixture(eventID: String) throws {
        guard app.state == .runningForeground else {
            throw NSError(domain: "Fotty.HomeDetailsUITest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App unavailable during saved-state restoration"])
        }
        let save = app.buttons["match-details-save"]
        if !save.exists {
            let menu = app.buttons["home-event-\(eventID)"]
            try reveal(menu)
            guard menu.exists else {
                throw NSError(domain: "Fotty.HomeDetailsUITest", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Original fixture state cannot be identified"])
            }
            if !isSavedOnHome(eventID) { return }
            menu.press(forDuration: 1.0)
            let details = app.buttons["Match details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 5))
            tap(details)
        }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        try reveal(save)
        if save.label == "Remove from My Matchday" { tap(save) }
        XCTAssertTrue(waitUntil(timeout: 5) { save.label == "Save to My Matchday" })
        let close = app.navigationBars["Match details"].buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        tap(close)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !save.exists && !self.isSavedOnHome(eventID)
        })
    }

    private func isSavedOnHome(_ eventID: String) -> Bool {
        app.descendants(matching: .any)["match-saved-\(eventID)"].firstMatch.exists
    }

    private func openHomeInterestEditor() throws {
        try selectTab("tab-home", surface: "Home scope and interest editor")
        // Home may retain a pushed editor; this is the same native destination,
        // not permission to reset the owner's navigation or preferences.
        if !app.descendants(matching: .any)["interest-browse-sport"].firstMatch.exists {
            let scope = app.buttons["home-selected-scope"]
            try reveal(scope)
            tap(scope)
            let edit = app.buttons["dashboard-home-interests-edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            tap(edit)
        }
        // Browse scope is editor-only state. The revised single editor no
        // longer displays every sport's whole-sport row simultaneously.
        try browseInterestSport("Cricket", category: "cricket")
        XCTAssertTrue(app.buttons["interest-sport-cricket"].waitForExistence(timeout: 5))
    }

    private func browseInterestSport(_ title: String, category: String) throws {
        let row = app.buttons["interest-sport-\(category)"]
        if row.exists && row.isHittable { return }
        let picker = app.descendants(matching: .any)["interest-browse-sport"].firstMatch
        try revealHomeInterestControl(picker, towardTop: true)
        tap(picker)
        let choice = app.buttons[title].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        tap(choice)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    /// SwiftUI's lazy List is a CollectionView on the physical iPad. Controls
    /// beyond its viewport may not exist in AX yet; scroll its native container
    /// before asserting reachability, without changing a followed preference.
    private func revealHomeInterestControl(_ element: XCUIElement, towardTop: Bool = false) throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let list = app.collectionViews.allElementsBoundByIndex
                .filter { $0.isHittable }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? visibleContentScroll
            guard list.exists && list.isHittable else { break }
            if towardTop || (element.exists && element.frame.maxY < list.frame.minY) { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable,
                      "The existing Home interests control is not reachable in its native List")
    }

    /// The186 editor must preview the same saved choices while its browsing
    /// scope changes. No sport, team, competition or filtering switch is edited.
    func testPhysical186InterestPreviewAndSportBrowsingPreserveSelection() throws {
        try openHomeInterestEditor()
        let cricket = app.buttons["interest-sport-cricket"]
        try reveal(cricket)
        let cricketChoice = try XCTUnwrap(cricket.value as? String)
        let onlySelected = app.switches["interest-only-selected"]
        try reveal(onlySelected)
        let originalScope = try XCTUnwrap(onlySelected.value as? String)
        let preview = app.descendants(matching: .any)["interest-home-preview"].firstMatch
        XCTAssertTrue(preview.exists)
        try reveal(preview)
        captureEvidence(surface: "186Home interests native preview with existing saved selection")

        try browseInterestSport("Football", category: "football")
        let football = app.buttons["interest-sport-football"]
        let footballChoice = try XCTUnwrap(football.value as? String)
        XCTAssertTrue(app.staticTexts["Competitions"].exists)
        try revealHomeInterestControl(app.buttons["interest-choose-teams"])
        try browseInterestSport("Cricket", category: "cricket")
        XCTAssertEqual(cricket.value as? String, cricketChoice)
        XCTAssertEqual(onlySelected.value as? String, originalScope)
        try browseInterestSport("Football", category: "football")
        XCTAssertEqual(football.value as? String, footballChoice)
        XCTAssertEqual(onlySelected.value as? String, originalScope)
        captureEvidence(surface: "186interest browsing scope changes without changing follows or filtering")
        let done = app.navigationBars["Home interests"].buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        tap(done)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !self.app.descendants(matching: .any)["interest-browse-sport"].firstMatch.exists
        })
        try selectTab("tab-home", surface: "Home after read-only interests preview gate")
        capturedFocusedEnd = true
    }

    /// Use a real, currently rendered date group. No saved fixture is created
    /// merely to make this control appear; absence is an explicit open gate.
    func testPhysical186MatchdayDayJumpUsesAnExistingDateSection() throws {
        try selectTab("tab-arena", surface: "186Full Matchday day navigation")
        let mode = app.segmentedControls["matchday-view-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertTrue(mode.buttons["Full Matchday"].isSelected)
        let jump = app.buttons["matchday-day-jump"]
        guard jump.waitForExistence(timeout: 15) else {
            captureEvidence(surface: "186day-jump pending: personal plan has fewer than two rendered eligible sections")
            throw XCTSkip("The current saved/followed schedule does not expose multiple jump destinations; no fixture was invented.")
        }
        tap(jump)
        let reviewedLabel = ProcessInfo.processInfo.environment["FOTTY_MATCHDAY_DAY_LABEL"]
        let target: XCUIElement?
        if let reviewedLabel {
            guard !reviewedLabel.isEmpty, reviewedLabel.count <= 160,
                  !reviewedLabel.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                return XCTFail("A reviewed day-jump label must be a bounded current native menu label")
            }
            target = app.buttons[reviewedLabel].firstMatch
        } else {
            target = app.buttons.matching(NSPredicate(format:
                "label MATCHES %@", "^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), .+"))
                .allElementsBoundByIndex.first { $0.isHittable }
        }
        guard let target, target.exists, target.isHittable else {
            let now = app.buttons["Live now"].firstMatch
            let next = app.buttons["Next up"].firstMatch
            let listed = app.buttons["Broadcast listed"].firstMatch
            if now.exists && now.isHittable { tap(now) }
            else if next.exists && next.isHittable { tap(next) }
            else if listed.exists && listed.isHittable { tap(listed) }
            throw XCTSkip("No nonempty dated destination was exposed in the current native menu; actual day scrolling remains unqualified.")
        }
        let title = target.label
        tap(target)
        let heading = app.staticTexts[title].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { heading.exists && heading.isHittable },
                      "The day-jump action did not reveal its existing section heading")
        XCTAssertTrue(mode.buttons["Full Matchday"].isSelected, "Jumping must not change the viewing scope")
        XCTAssertFalse(app.descendants(matching: .any)["matchday-viewing-duration"].firstMatch.exists)
        XCTAssertEqual(app.state, .runningForeground)
        captureEvidence(surface: "186native day jump reveals existing \(title) section")
        try selectTab("tab-home", surface: "Home after existing-day Matchday jump")
        capturedFocusedEnd = true
    }

    /// Read the new service's real default-off control and current continuity
    /// status. Never enable cloud/background work or synthesize a retry error.
    func testPhysical186BackgroundReminderAndContinuityControlsPreserveConsent() throws {
        try selectTab("tab-settings", surface: "186reminder background consent")
        let notifications = app.buttons["settings-notifications"]
        try reveal(notifications)
        tap(notifications)
        let background = app.switches["sports-reminder-background-toggle"]
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        let originalBackground = try XCTUnwrap(background.value as? String)
        guard originalBackground == "0" else {
            throw XCTSkip("The owner already enabled background reminder maintenance; preserve that opt-in rather than reset it to test a default.")
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        captureEvidence(surface: "186background reminder maintenance remains off without permission prompt")
        let back = app.navigationBars.buttons["Settings"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        tap(back)
        let continuity = app.buttons["settings-sports-continuity"]
        try reveal(continuity)
        tap(continuity)
        let sync = app.switches["sports-sync-toggle"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        let originalSync = try XCTUnwrap(sync.value as? String)
        let retry = app.buttons["sports-continuity-retry"]
        let widgetRetry = app.buttons["sports-widget-retry"]
        let hadRetry = retry.exists, hadWidgetRetry = widgetRetry.exists
        if hadRetry {
            XCTAssertTrue(app.descendants(matching: .any)["sports-local-apply-error"].firstMatch.exists)
            try reveal(retry)
            tap(retry)
            XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .runningForeground && sync.value as? String == originalSync })
        }
        // The first retry also attempts the widget snapshot. Re-query rather
        // than demand a button whose real error may already have recovered.
        if widgetRetry.exists {
            XCTAssertTrue(app.descendants(matching: .any)["sports-widget-write-error"].firstMatch.exists)
            try reveal(widgetRetry)
            tap(widgetRetry)
            XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .runningForeground && sync.value as? String == originalSync })
        }
        XCTAssertEqual(sync.value as? String, originalSync)
        XCTAssertTrue(app.staticTexts["My Matchday widget"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        navigationTimings.append("186continuity consent unchanged. Actual local-apply retry visible=\(hadRetry); actual widget retry visible=\(hadWidgetRetry). Absent real errors are not a retry-recovery pass; no cloud/background opt-in, fake failure, widget installation or delivery claim.")
        captureEvidence(surface: "186sports continuity current statuses and explicit retry routes")
        tap(app.navigationBars.buttons["Settings"].firstMatch)
        try reveal(notifications)
        tap(notifications)
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        XCTAssertEqual(background.value as? String, originalBackground)
        try selectTab("tab-home", surface: "Home after unchanged continuity/background consent checks")
        capturedFocusedEnd = true
    }

    func testPhysicalProductionHomeMatchdaySearchJourney() throws {
        for iteration in 0..<2 {
            try selectTab("tab-arena", surface: "Matchday")
            let scroll = visibleContentScroll
            if scroll.exists { scroll.swipeUp(); scroll.swipeDown() }
            XCTAssertEqual(app.state, .runningForeground)
            if iteration == 0 { captureEvidence(surface: "Production Matchday with lazy rows") }
            try selectTab("tab-home", surface: "Home")
        }

        try openSearch()
        navigationTimings.append("Search coverage: exact complete queries and latest settled results; not per-prefix stress or isolated latency.")
        let field = app.searchFields.firstMatch
        for term in ["football", "cricket", "zz"] {
            let started = Date()
            try replaceSearchText(with: term)
            XCTAssertTrue(waitUntil(timeout: 5) {
                field.value as? String == term
                    && !self.app.staticTexts["Searching…"].exists
                    && (self.app.staticTexts["No matching fixtures or channels"].exists
                        || self.app.descendants(matching: .any).matching(
                            NSPredicate(format: "identifier BEGINSWITH %@", "search-result-")
                        ).count > 0)
            }, "Production Search did not settle for the latest query")
            navigationTimings.append("Search settled: \(Int(Date().timeIntervalSince(started) * 1_000)) ms")
        }
        tap(app.buttons["Done"].firstMatch)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !self.searchSurface.exists && self.tabControl("tab-home").isHittable
        })
        endSurface = "Production Home after Matchday and Search"
    }

    /// Isolate Search from Matchday/catalog navigation, then exercise both
    /// retained scene text and Clear-to-new-query transitions. Each replacement
    /// uses one complete native typing event; never repair a missing suffix.
    func testPhysicalSearchClearRetypeAndReopenPreservesExactInput() throws {
        try openSearch()
        for term in ["football", "cricket", "zz", "cricket"] {
            try replaceSearchText(with: term)
            let field = searchSurface.searchFields.firstMatch
            XCTAssertTrue(waitUntil(timeout: 5) {
                field.value as? String == term
                    && !self.app.staticTexts["Searching…"].exists
                    && (self.app.staticTexts["No matching fixtures or channels"].exists
                        || self.searchSurface.descendants(matching: .any).matching(
                            NSPredicate(format: "identifier BEGINSWITH %@", "search-result-")
                        ).count > 0)
            }, "Search must settle the complete latest query without changing its text")
            tap(app.buttons["Done"].firstMatch)
            XCTAssertTrue(waitUntil(timeout: 5) { !self.searchSurface.exists })
            try openSearch()
            XCTAssertEqual(searchSurface.searchFields.firstMatch.value as? String, term,
                           "Reopening Search must restore the exact committed query")
        }
        captureEvidence(surface: "Search complete-query replacement and scene restoration")
        tap(app.buttons["Done"].firstMatch)
        XCTAssertTrue(waitUntil(timeout: 5) { !self.searchSurface.exists })
        capturedFocusedEnd = true
    }

    /// Separate from the complete-string XCTest event above: press the actual
    /// exposed software keys once each from blank. A pass here cannot erase
    /// a failed burst-input receipt or justify repairing its partial suffix.
    func testPhysical186SearchNativeKeysCommitAndSettleACompleteCricketQuery() throws {
        try openSearch()
        let field = searchSurface.searchFields.firstMatch
        tap(field)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let retained = field.value as? String ?? ""
        if !retained.isEmpty && retained != field.placeholderValue {
            let clear = field.buttons["Clear text"].firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 3))
            tap(clear)
        }
        XCTAssertTrue(waitUntil(timeout: 3) {
            let value = field.value as? String ?? ""
            return value.isEmpty || value == field.placeholderValue
        }, "The separate native-key gate must begin with a genuinely empty Search field")
        tap(field)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        // Key is a public XCUI element type exposed by this real keyboard.
        // Observe its actual case immediately before each single tap: native
        // auto-capitalization may change after the first character.
        // Never synthesize text, paste, write query state, or continue a suffix.
        var expected = ""
        for letter in ["c", "r", "i", "c", "k", "e", "t"] {
            let query = keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", letter))
            XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 3))
            let exposed = query.allElementsBoundByAccessibilityElement.filter { $0.isHittable }
            XCTAssertEqual(exposed.count, 1, "The next native letter key must be uniquely exposed")
            let key = try XCTUnwrap(exposed.first)
            let observed = key.label
            XCTAssertEqual(observed.count, 1)
            XCTAssertEqual(observed.lowercased(), letter)
            expected += observed
            tap(key)
        }
        XCTAssertEqual(expected.count, 7)
        XCTAssertEqual(expected.lowercased(), "cricket")
        let committed = waitUntil(timeout: 3) { field.value as? String == expected }
        let receipt = XCTAttachment(string: "Seven exposed native software-key taps from verified blank: c,r,i,c,k,e,t, using each key's actual case immediately before tapping. Expected=\(expected); observed=\((field.value as? String ?? "").prefix(120)); exact match=\(committed); expected case-fold=\(expected.lowercased()). No complete-string event, suffix repair, paste or query hook. This separate result does not replace the burst-input gate.")
        receipt.name = "Separate native-key Search committed-query receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(committed, "The native software-key path lost Search input")
        XCTAssertTrue(waitUntil(timeout: 5) {
            field.value as? String == expected && !self.app.staticTexts["Searching…"].exists
                && (self.app.staticTexts["No matching fixtures or channels"].exists
                    || self.searchSurface.descendants(matching: .any).matching(
                        NSPredicate(format: "identifier BEGINSWITH %@", "search-result-")).count > 0)
        }, "The native-key query did not settle its latest complete result state")
        captureEvidence(surface: "Separate186native-key complete cricket Search; burst-input result remains independent")
        tap(app.buttons["Done"].firstMatch)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !self.searchSurface.exists && self.tabControl("tab-home").isHittable
        })
        capturedFocusedEnd = true
        endSurface = "Home after separate native-key Search gate"
    }

    /// No fixture launch flags or exemptions: unresolved issues retain Apple's
    /// default failure. This complements deterministic component snapshots.
    func testPhysicalProductionAccessibilitySurfaces() throws {
        for (identifier, surface) in [("tab-home", "Home"), ("tab-arena", "Matchday"), ("tab-settings", "Settings")] {
            try selectTab(identifier, surface: surface)
            captureEvidence(surface: "Production \(surface) before accessibility audit")
            try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .hitRegion, .textClipped, .trait])
        }
        try selectTab("tab-home", surface: "Home after production accessibility audits")
    }

    /// Capability activation must not opt the owner into cloud transfers.
    /// Read the real control and disclosure; never toggle or reset preferences.
    func testPhysicalSportsContinuityRemainsOptIn() throws {
        try selectTab("tab-settings", surface: "Settings")
        let continuity = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@", "Sports continuity"
        )).firstMatch
        try reveal(continuity)
        tap(continuity)
        let toggle = app.switches["sports-sync-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "Signing the capability must not enable sports transfers")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "FPL, reminders, viewing history and stream links are not included"
        )).firstMatch.exists)
        captureEvidence(surface: "Sports continuity remains off with explicit sports-only disclosure")
        try selectTab("tab-home", surface: "Home after opt-in continuity verification")
        capturedFocusedEnd = true
    }

    /// Read-only: the Highfly setup journey shows its two steps and the system
    /// Paste control. Nothing is pasted, saved, enabled or removed.
    func testPhysicalHighflySetupShowsTwoStepsWithPaste() throws {
        try selectTab("tab-settings", surface: "Settings")
        let sources = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Playback sources")).firstMatch
        try reveal(sources)
        tap(sources)
        let highfly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Highfly")).firstMatch
        try reveal(highfly)
        captureEvidence(surface: "Playback sources with Highfly setup row")
        tap(highfly)
        XCTAssertTrue(app.links["source-setup-open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["source-setup-paste"].exists || app.otherElements["source-setup-paste"].exists)
        XCTAssertTrue(app.secureTextFields["source-setup-link"].exists)
        captureEvidence(surface: "Highfly setup: two steps, Paste and typed fallback")
        // Settings is a sheet over Home: leave through its own navigation.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { tap(back) }
        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 3) { tap(done) }
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 5))
        capturedFocusedEnd = true
    }

    /// Explicit owner-authorized, single-iPad opt-in check. A queued status is
    /// not proof of delivery to another device. Always restore sync to off;
    /// no preference, saved match, journal or account is reset to pass this.
    func testPhysicalSportsSyncQueuesWithoutWaitingForNotificationAndReturnsOff() throws {
        guard ProcessInfo.processInfo.environment["FOTTY_ALLOW_TEMPORARY_SPORTS_SYNC"] == "1" else {
            throw XCTSkip("Temporary real sports-only iCloud opt-in needs the approved gate flag.")
        }
        try selectTab("tab-settings", surface: "Settings sports-only sync gate")
        let continuity = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@", "Sports continuity"
        )).firstMatch
        try reveal(continuity)
        tap(continuity)
        let toggle = app.switches["sports-sync-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        guard toggle.value as? String == "0" else {
            throw XCTSkip("Sync was already on; preserve the owner's state instead of changing existing consent.")
        }
        defer {
            if toggle.exists && toggle.value as? String == "1" { tap(toggle) }
        }
        for phase in ["first opt-in", "unchanged re-enable"] {
            tap(toggle)
            guard waitUntil(timeout: 15, {
                toggle.value as? String == "1" && app.staticTexts["iCloud updates queued"].exists
            }) else {
                captureEvidence(surface: "Real single-Jet sync \(phase) did not queue")
                XCTFail("Sports sync did not reach a real queued state within its bounded \(phase); no synthetic cloud notification was supplied.")
                return
            }
            captureEvidence(surface: "Real single-Jet sports sync \(phase): queued, not delivered")
            tap(toggle)
            XCTAssertTrue(waitUntil(timeout: 5, { toggle.value as? String == "0" }))
        }
        XCTAssertEqual(toggle.value as? String, "0")
        captureEvidence(surface: "Sports sync restored to off; local setup retained")
        capturedFocusedEnd = true
    }

    /// Read the native gallery preview without adding a widget or changing the
    /// owner's Home layout. This qualifies discovery/empty rendering only;
    /// gallery snapshots are not installed-widget timeline or tap evidence.
    func testPhysicalSportsWidgetGalleryEmptyState() throws {
        executionTimeAllowance = 180
        capturedFocusedEnd = true // Fotty is backgrounded during this check.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer { restoreHomeAfterWidgetGallery(springboard) }
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        guard waitUntil(timeout: 5, { springboard.state == .runningForeground }) else {
            throw XCTSkip("SpringBoard did not expose the native widget-gallery route.")
        }
        let icon = springboard.icons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@ AND NOT label CONTAINS[c] %@ AND NOT label CONTAINS[c] %@",
            "Fotty", "UITest", "Runner"
        )).allElementsBoundByIndex.prefix(4).first { $0.exists && $0.isHittable }
        guard let icon else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Fotty icon unavailable")
            throw XCTSkip("No visible Fotty Home icon was available; the owner's pages were not rearranged.")
        }
        icon.press(forDuration: 1.1)
        // iPadOS 27 Dock icons first expose an Open Windows menu. Its observed
        // Options submenu, not a window action, owns ordinary Home editing.
        if widgetGalleryControl(springboard, labels: ["Edit Home Screen"], timeout: 0.3) == nil,
           let options = widgetGalleryControl(springboard, labels: ["Options"], timeout: 0.3) {
            options.tap()
        }
        guard let editHome = widgetGalleryControl(springboard, labels: ["Edit Home Screen"], timeout: 4) else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Home edit route unavailable")
            throw XCTSkip("The native Fotty icon menu did not expose Edit Home Screen.")
        }
        editHome.tap()
        guard let edit = widgetGalleryControl(springboard, labels: ["Edit"], timeout: 4) else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Edit menu unavailable")
            throw XCTSkip("The native Home edit menu was unavailable; widget rendering remains unqualified.")
        }
        edit.tap()
        guard let add = widgetGalleryControl(springboard, labels: ["Add Widget", "Add Widgets"], timeout: 4) else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Gallery entry unavailable")
            throw XCTSkip("The native Edit menu did not expose the widget gallery.")
        }
        add.tap() // Entry menu only. Never press the gallery's Add Widget button.
        let search = springboard.searchFields.firstMatch
        guard waitUntil(timeout: 5, { search.exists && search.isHittable }) else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Gallery search unavailable")
            throw XCTSkip("The native widget gallery did not expose its search field.")
        }
        search.tap()
        search.typeText("Fotty")
        let appNames = ["Fotty Sports Hub", "FottySportsHub", "Fotty"]
        var choseEntry = false
        for name in appNames {
            let cell = springboard.cells.containing(.staticText, identifier: name).firstMatch
            if cell.exists && cell.isHittable { cell.tap(); choseEntry = true; break }
        }
        if !choseEntry, let entry = widgetGalleryControl(springboard, labels: appNames, timeout: 2) {
            entry.tap(); choseEntry = true
        }
        if !choseEntry {
            // The observed iPad sidebar exposes a visible UILabel leaf, not a
            // hittable button. A normal tap at that exact visible label is safe
            // only in the verified widget-search context; it is not a forced tap.
            for name in appNames {
                let text = springboard.staticTexts[name].firstMatch
                let window = springboard.windows.firstMatch
                if search.value as? String == "Fotty", text.exists,
                   widgetGalleryElementIsVisible(text, in: springboard), window.exists,
                   text.frame.maxX < window.frame.width * 0.4 {
                    text.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
                    choseEntry = true
                    break
                }
            }
        }
        guard choseEntry else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Fotty gallery entry unavailable")
            throw XCTSkip("No verified visible Fotty widget-sidebar entry was reachable; no widget was added.")
        }
        let title = springboard.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Your sports plan"
        )).firstMatch
        let expectedEmpty = springboard.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Save a match in Fotty"
        )).firstMatch
        // A gallery may initially show another existing Fotty widget/family.
        // Only swipe while its native Add Widget footer confirms this surface;
        // never invoke that footer, add a widget, or touch FPL preferences.
        var reachedSports = false
        for page in 0..<6 {
            if waitUntil(timeout: 2, { self.widgetGalleryElementIsVisible(title, in: springboard) }) {
                reachedSports = true
                break
            }
            if let sportsChoice = widgetGalleryControl(springboard, labels: ["Your sports plan"], timeout: 0.3) {
                sportsChoice.tap()
                continue
            }
            guard page < 5,
                  widgetGalleryControl(springboard, labels: ["Add Widget", "Add Widgets"], timeout: 0.3) != nil else { break }
            springboard.swipeLeft()
        }
        guard reachedSports else {
            captureSportsWidgetGalleryEvidence(springboard, stage: "Sports preview unreachable")
            throw XCTSkip("The bounded native gallery route could not reach Your sports plan; its rendering remains unqualified.")
        }
        let decodedEmpty = waitUntil(timeout: 5) {
            self.widgetGalleryElementIsVisible(expectedEmpty, in: springboard)
        }
        captureSportsWidgetGalleryEvidence(springboard, stage: "Your sports plan empty preview")
        guard decodedEmpty else {
            // Missing storage instead renders Open Fotty for your plan. Do not
            // mistake that placeholder/fallback for the verified empty receipt.
            throw NSError(domain: "Fotty.SportsWidgetGallery", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Your sports plan was reachable but did not render Save a match in Fotty from the verified empty sports snapshot."
            ])
        }
        endSurface = "Sports widget native empty gallery preview; no widget added"
    }

    /// The reported 10 October fixtures have explicit terminal publisher facts.
    /// Their absence is acceptable; neither may remain a LIVE/Watch-now row.
    /// This is a real-feed UI regression, not synthetic full-time injection.
    func testPhysicalProductionReportedFinalsDoNotReturnToLive() throws {
        let scroll = visibleContentScroll
        if scroll.exists { scroll.swipeDown() }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            XCTAssertEqual(app.state, .runningForeground)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        var inspectedHomeRows = 0
        for _ in 0..<3 {
            let currentRows = app.descendants(matching: .any).matching(identifier: "home-watch-now").allElementsBoundByIndex
            inspectedHomeRows += currentRows.count
            for row in currentRows {
                let text = row.debugDescription.lowercased()
                XCTAssertFalse(text.contains("sunderland") && text.contains("brighton"), "Finished Sunderland–Brighton returned to current broadcasts")
                XCTAssertFalse(text.contains("chelsea") && text.contains("bournemouth"), "Finished Chelsea–Bournemouth returned to current broadcasts")
            }
            if scroll.exists { scroll.swipeUp() }
        }
        XCTAssertGreaterThan(inspectedHomeRows, 0, "No current production broadcast rows were available to inspect")
        captureEvidence(surface: "Production Home after explicit full-time receipts")
        try selectTab("tab-arena", surface: "Production Matchday after explicit full-time receipts")
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "matchday-row-")
        )
        XCTAssertTrue(rows.firstMatch.exists, "No production Matchday rows were available to inspect")
        // SwiftUI propagates a container identifier to some descendants. Do not
        // enumerate every descendant and fetch a fresh full AX tree per child:
        // that can exhaust the physical runner's allowance on a large catalog.
        // Check only the two reported fixture identities, in either catalog lane.
        var presentReportedRows = 0
        for fixtureID in ["560592", "560595"] {
            for identifier in ["matchday-row-\(fixtureID)", "matchday-row-sports-fixture:premier-league:\(fixtureID)"] {
                let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
                if row.exists {
                    presentReportedRows += 1
                    XCTAssertFalse(row.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "LIVE")).firstMatch.exists,
                                   "Matchday retained a finished fixture as LIVE")
                }
            }
        }
        let coverage = XCTAttachment(string: "Inspected current Home rows across three viewports: \(inspectedHomeRows); Matchday has production rows; reported fixture routes present: \(presentReportedRows). Both dated terminal identities were queried in the registry and legacy lanes. Absence is acceptable after terminal catalog reconciliation.")
        coverage.name = "Production terminal-regression coverage"
        coverage.lifetime = .keepAlways
        add(coverage)
        captureEvidence(surface: "Production Matchday terminal-status regression")
        try selectTab("tab-home", surface: "Production Home after finished-status checks")
        endSurface = "Production Home terminal-status regression completed"
    }

    /// Repeated real pull-to-refresh gives an attached trace actual catalog
    /// work instead of mistaking an idle, already-settled Home for proof.
    func testPhysicalProductionRefreshWorkload() throws {
        let attachWindow = Date().addingTimeInterval(12)
        while Date() < attachWindow {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        for _ in 0..<2 {
            let scroll = visibleContentScroll
            XCTAssertTrue(scroll.exists && scroll.isHittable)
            scroll.swipeDown()
            let settleWindow = Date().addingTimeInterval(20)
            while Date() < settleWindow {
                XCTAssertEqual(app.state, .runningForeground)
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        try openSearch()
        try replaceSearchText(with: "zz")
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.app.searchFields.firstMatch.value as? String == "zz"
                && self.app.staticTexts["No matching fixtures or channels"].exists
        })
        let searchWindow = Date().addingTimeInterval(20)
        while Date() < searchWindow {
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertEqual(app.searchFields.firstMatch.value as? String, "zz")
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        tap(app.buttons["Done"].firstMatch)
        XCTAssertTrue(waitUntil(timeout: 5) { !self.searchSurface.exists && self.tabControl("tab-home").isHittable })
        endSurface = "Production Home after two real refreshes and settled Search"
    }

    func testPhysicalProductionPlaybackSourceSwitchAndReturn() throws {
        // The local counter is a fresh before/after UI receipt. Loading ending
        // alone is not video proof, and muted hardware tests cannot prove audio.
        let before = try readProvenStartsThroughExistingSettings()
        try selectTab("tab-home", surface: "Home")
        try openRealPlayback()
        try waitForStartupUI(timeout: 65)

        try openSources()
        let rows = sourceRows
        guard rows.count >= 2 else {
            try closeSourceSheetIfPresent()
            try closePlayer()
            throw XCTSkip("The real selected broadcast currently has only one source; switching cannot be qualified.")
        }
        let alternate = rows.allElementsBoundByIndex.first { !$0.isSelected }
        let chosen = try XCTUnwrap(alternate, "The source picker did not expose an unselected source")
        let selectedIdentifier = chosen.identifier
        tap(chosen)
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["Close broadcast sources"].exists })
        try waitForStartupUI(timeout: 65)
        try openSources()
        XCTAssertTrue(app.buttons[selectedIdentifier].isSelected,
                      "The requested source did not become selected, or immediately failed over")
        try closeSourceSheetIfPresent()
        captureEvidence(surface: "Production playback after source switch; UI evidence only")
        capturedFocusedEnd = true
        try closePlayer()

        let after = try readProvenStartsThroughExistingSettings()
        navigationTimings.append("Bounded local Proven starts counter: before=\(before), after=\(after)")
        guard after > before else {
            // The 250-event ring can evict older starts as new events arrive.
            // A flat aggregate is unknown, not proof that this stream failed.
            throw XCTSkip("No net increase in bounded local decoded-start evidence; a current-session receipt is required before claiming fresh video proof.")
        }
        try selectTab("tab-home", surface: "Home after real playback and source switch")
        XCTAssertFalse(player.exists)
    }

    /// Exercise the retained scene owner, not a second hidden player. Native
    /// identity comparison is required when a real native layer is present;
    /// Web surfaces retain a separate provider-video acceptance gate.
    func testPhysicalViewingSessionMinimizeBrowseReturnAndStop() throws {
        if hasReviewedCommunitySourceConfiguration {
            executionTimeAllowance = 300
            let qualified = try qualifyReviewedCommunitySource(leavePlayerOpen: true)
            try verifyQualifiedCommunitySource(qualified)
            let current = try readNativeMeasurement()
            assertNativeIdentity(current, matches: qualified.nativeMeasurement,
                                 message: "Reviewed retained viewing must start on its qualified native item/attempt")
        } else {
            try openRealPlayback()
            try waitForStartupUI(timeout: 65)
        }
        XCTAssertTrue(app.buttons["viewing-minimize"].waitForExistence(timeout: 5))
        // exists reports raw XCTest hierarchy membership, not VoiceOver focus.
        // Keep retained owners mounted; qualify touch isolation here and retain
        // a separate real assistive-navigation gate for the modal region.
        for identifier in ["home-search", "home-settings", "tab-home", "tab-arena"] {
            let background = app.buttons[identifier].firstMatch
            if background.exists {
                XCTAssertFalse(background.isHittable,
                               "Expanded viewing must block inactive background control \(identifier)")
            }
        }
        navigationTimings.append("Expanded-shell touch isolation is checked. XCTest raw-tree membership is not VoiceOver modal-navigation proof; actual assistive navigation remains a separate gate.")
        let usesNativeTransport = readNativeMeasurement(identifier: "native-playback-measurement") != nil
        try pauseViewingThroughCanonicalControl(usesNativeTransport: usesNativeTransport)
        let before = readNativeMeasurement(identifier: "native-playback-measurement")
        assertViewingPause(usesNativeTransport: usesNativeTransport)
        if let before { attachNativeMeasurementScalars(before, name: "Paused viewing identity before compact navigation") }
        captureEvidence(surface: "Viewing experience single match before minimizing")
        tap(app.buttons["viewing-minimize"])
        XCTAssertTrue(app.buttons["viewing-mini-expand"].waitForExistence(timeout: 5))
        for (tab, name) in [("tab-arena", "Matchday with compact player"), ("tab-settings", "Settings with compact player"), ("tab-home", "Home with compact player")] {
            try selectTab(tab, surface: name)
            XCTAssertTrue(app.buttons["viewing-mini-expand"].exists,
                          "Browsing must retain the compact viewing owner")
        }
        XCTAssertTrue(app.buttons["home-search"].isHittable,
                      "Minimizing must restore ordinary Home controls")
        captureEvidence(surface: "Native compact player while browsing Home")
        tap(app.buttons["viewing-mini-expand"])
        XCTAssertTrue(app.buttons["viewing-sources"].waitForExistence(timeout: 5))
        let after = readNativeMeasurement(identifier: "native-playback-measurement")
        if let before, let after {
            XCTAssertEqual(before["itemToken"] as? String, after["itemToken"] as? String,
                           "Presentation continuity replaced the native item")
            XCTAssertEqual(before["attemptToken"] as? String, after["attemptToken"] as? String,
                           "Presentation continuity began another source attempt")
        }
        assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                           message: "Restoring paused compact viewing")
        assertViewingPause(usesNativeTransport: usesNativeTransport)
        navigationTimings.append("Compact-player journey completed; native identity receipt available=\(before != nil && after != nil). Absent/Web measurements are unknown, not decoded-video proof.")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.buttons["viewing-details"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["viewing-control-dock"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["viewing-companion"].firstMatch.exists)
            tap(app.buttons["viewing-details"])
            let done = app.buttons["viewing-details-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            captureEvidence(surface: "Paused video-first Details sheet")
            tap(done)
            XCTAssertTrue(waitUntil(timeout: 5) { !done.exists })
            assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                               message: "Details Done while deliberately paused")
            assertViewingPause(usesNativeTransport: usesNativeTransport)
            try exerciseVideoFirstRotation(before: before, preservesPause: true, usesNativeTransport: usesNativeTransport)
        } else {
            let focus = app.buttons["viewing-focus-video"]
            let options = app.buttons["viewing-options"]
            try reveal(options)
            tap(options)
            XCTAssertTrue(focus.waitForExistence(timeout: 5))
            tap(focus)
            XCTAssertTrue(app.buttons["viewing-exit-focus"].waitForExistence(timeout: 5))
            assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                               message: "Entering Focus while deliberately paused")
            captureEvidence(surface: "Paused viewing Focus preserves the retained surface")
            try exercisePausedViewingFocusRotation(before: before, usesNativeTransport: usesNativeTransport)
            tap(app.buttons["viewing-exit-focus"])
            XCTAssertTrue(app.buttons["viewing-sources"].waitForExistence(timeout: 5))
            assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                               message: "Leaving Focus while deliberately paused")
            assertViewingPause(usesNativeTransport: usesNativeTransport)
        }
        try openSources()
        try closeSourceSheetIfPresent()
        for rawURL in ["fotty://sports-plan", "fotty://matchday"] {
            let url = try XCTUnwrap(URL(string: rawURL))
            #if !targetEnvironment(macCatalyst)
            XCUIDevice.shared.system.open(url)
            #endif
            XCTAssertTrue(app.buttons["viewing-mini-expand"].waitForExistence(timeout: 8),
                          "A sports widget route must reveal Matchday, not leave expanded video covering it")
            let mode = app.segmentedControls["matchday-view-mode"]
            XCTAssertTrue(mode.waitForExistence(timeout: 5))
            try reveal(mode)
            XCTAssertTrue(mode.isHittable)
            tap(app.buttons["viewing-mini-expand"])
            XCTAssertTrue(app.buttons["viewing-sources"].waitForExistence(timeout: 5))
            assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                               message: "Warm sports-widget navigation preserves the paused owner")
            assertViewingPause(usesNativeTransport: usesNativeTransport)
        }
        captureEvidence(surface: "Viewing experience restored after browsing and Sources")
        try closePlayer()
        XCTAssertFalse(app.buttons["viewing-mini-expand"].exists)
        try selectTab("tab-home", surface: "Home after warm widget navigation and Stop")
        XCTAssertTrue(app.buttons["home-search"].isHittable,
                      "Stopping must restore ordinary Home controls")
        capturedFocusedEnd = true
    }

    func testPhysicalViewingWatchTwoIndependentSourcesAudioAndReturn() throws {
        // Two real source startups retain their existing 65-second grace;
        // this gate must not fail merely because it now exercises both choices.
        executionTimeAllowance = 420
        try openRealPlayback()
        try waitForStartupUI(timeout: 65)
        let original = readNativeMeasurement(identifier: "native-playback-measurement")
        tap(app.buttons["viewing-watch-two"])
        let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-second-match-"))
        guard candidates.firstMatch.waitForExistence(timeout: 10),
              let candidate = candidates.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            if app.buttons["Done"].firstMatch.exists { tap(app.buttons["Done"].firstMatch) }
            try closePlayer()
            throw XCTSkip("No eligible real second match was available; no synthetic fixture was injected.")
        }
        tap(candidate)
        let panes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-pane-source-"))
        XCTAssertTrue(waitUntil(timeout: 55) { panes.count == 2 }, "The second real lookup did not produce two independent pane controls")
        let controls = panes.allElementsBoundByIndex
        let identities = Set(controls.map(\.identifier))
        XCTAssertEqual(identities.count, 2)
        let firstReceipt = readNativeMeasurement(identifier: "native-measurement-pane-1")
        if let original, let firstReceipt {
            XCTAssertEqual(original["itemToken"] as? String, firstReceipt["itemToken"] as? String)
            XCTAssertEqual(original["attemptToken"] as? String, firstReceipt["attemptToken"] as? String)
        }
        for control in controls {
            tap(control)
            XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 5), "Each pane must open its own source picker")
            try closeSourceSheetIfPresent()
        }
        var switched: [Bool] = []
        for index in controls.indices {
            let sibling = controls[1 - index]
            switched.append(try switchCurrentViewingPaneSource(
                controls[index], measurementIdentifier: "native-measurement-pane-\(index + 1)",
                preserving: sibling, siblingMeasurementIdentifier: "native-measurement-pane-\(2 - index)"
            ))
        }
        let beforeSwap = [
            readNativeMeasurement(identifier: "native-measurement-pane-1"),
            readNativeMeasurement(identifier: "native-measurement-pane-2")
        ]
        let audio = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-pane-audio-"))
        XCTAssertEqual(audio.count, 2)
        for control in audio.allElementsBoundByIndex {
            tap(control)
            XCTAssertEqual(control.value as? String, "Selected")
            XCTAssertEqual(audio.allElementsBoundByIndex.filter { $0.value as? String == "Selected" }.count, 1)
        }
        tap(app.buttons["viewing-swap"])
        XCTAssertEqual(Set(panes.allElementsBoundByIndex.map(\.identifier)), identities,
                       "Swapping presentation must preserve both logical panes")
        for index in beforeSwap.indices {
            assertRetainedNativeViewingIdentity(beforeSwap[index], identifier: "native-measurement-pane-\(index + 1)",
                                               message: "Audio focus and Swap preserve logical pane \(index + 1)")
        }
        captureEvidence(surface: "Watch Two independent sources and audio focus; video receipts are separate")
        tap(app.buttons["viewing-return-one"])
        XCTAssertTrue(app.buttons["viewing-sources"].waitForExistence(timeout: 5))
        XCTAssertEqual(panes.count, 0)
        try closePlayer()
        capturedFocusedEnd = true
        navigationTimings.append("Current Watch Two actual alternate source selection: pane1=\(switched[0]), pane2=\(switched[1]); unavailable alternatives are not source-switch qualification. Selected audio values are control ownership, not audible exclusivity.")
        if switched.contains(false) {
            throw XCTSkip("One or both real alternate sources could not be qualified. Independent menus/audio/Swap/Return/Stop were exercised, but two-pane alternate switching remains unqualified.")
        }
    }

    /// A separate picture gate: source rows and loading completion cannot
    /// qualify two native videos. Each logical pane must retain its own ready,
    /// rendered, advancing item/attempt over three separated scalar samples
    /// before menus, source changes, audio focus or Swap are exercised.
    func testPhysicalViewingWatchTwoTwoNativePicturesAndOwnership() throws {
        executionTimeAllowance = 420
        if hasReviewedCommunitySourceConfiguration {
            let qualified = try qualifyReviewedCommunitySource(leavePlayerOpen: true, attemptTimeout: 90)
            try verifyQualifiedCommunitySource(qualified)
        } else {
            try openRealPlayback()
            try waitForStartupUI(timeout: 65)
        }
        let original = readNativeMeasurement(identifier: "native-playback-measurement")
        tap(app.buttons["viewing-watch-two"])
        let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-second-match-"))
        guard candidates.firstMatch.waitForExistence(timeout: 10),
              let candidate = try reviewedRealViewingSecondCandidate(in: candidates) else {
            if app.buttons["Done"].firstMatch.isHittable { tap(app.buttons["Done"].firstMatch) }
            try stopUnqualifiedViewing("No eligible reviewed real second match was reachable; no catalog row or source was injected.")
        }
        let chosenSecond = XCTAttachment(string: "Existing real second-match control: \(candidate.identifier); label=\(String(candidate.label.prefix(250))). No synthetic fixture or source activation.")
        chosenSecond.name = "Strict Watch Two real pair selection"
        chosenSecond.lifetime = .keepAlways
        add(chosenSecond)
        tap(candidate)
        let panes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-pane-source-"))
        guard waitUntil(timeout: 55, { panes.count == 2 }) else {
            try stopUnqualifiedViewing("The real second lookup did not yield two pane owners within its bounded setup; two pictures remain unqualified.")
        }
        let controls = panes.allElementsBoundByIndex
        let identities = Set(controls.map(\.identifier))
        XCTAssertEqual(identities.count, 2)
        guard var pictures = qualifyCurrentViewingNativePair(timeout: 65, evidenceName: "Initial two native pictures") else {
            try stopUnqualifiedViewing("Both real panes did not prove ready rendered native pixels and same-item/attempt media-time progress over three samples. Web or unavailable receipts are not native-picture success.")
        }
        XCTAssertNotEqual(pictures[0]["attemptToken"] as? String, pictures[1]["attemptToken"] as? String,
                          "Two logical native panes cannot share one source attempt")
        if let original {
            assertNativeIdentity(pictures[0], matches: original,
                                 message: "Adding the second real match replaced the previously native primary")
        }
        captureEvidence(surface: "Both real native pictures qualified before source and audio controls")
        for index in controls.indices {
            _ = try currentViewingSourceEvidence(in: controls[index])
            assertRetainedNativeViewingIdentity(pictures[index], identifier: "native-measurement-pane-\(index + 1)",
                                               message: "Opening a pane menu preserves its proven native item/attempt")
        }
        for index in controls.indices {
            let sibling = controls[1 - index]
            guard try switchCurrentViewingPaneSource(controls[index],
                measurementIdentifier: "native-measurement-pane-\(index + 1)",
                preserving: sibling, siblingMeasurementIdentifier: "native-measurement-pane-\(2 - index)") else {
                try stopUnqualifiedViewing("An actual alternate source was unavailable or acquired explicit failure/fallback evidence; fallback is not chosen-source success.")
            }
            let selected = try controls.map { try currentViewingSourceEvidence(in: $0) }
            guard let changedPictures = qualifyCurrentViewingNativePair(timeout: 35,
                evidenceName: "Two native pictures after pane \(index + 1) alternate") else {
                try stopUnqualifiedViewing("The requested real alternate did not retain two ready rendered and advancing native pictures; source selection alone is not success.")
            }
            for paneIndex in controls.indices {
                let settled = try currentViewingSourceEvidence(in: controls[paneIndex])
                if settled.selectedID != selected[paneIndex].selectedID {
                    XCTAssertTrue(!selected[paneIndex].retryIDs.contains(selected[paneIndex].selectedID)
                                  && settled.retryIDs.contains(selected[paneIndex].selectedID),
                                  "A source changed during native qualification without new exact failed-row/fallback evidence")
                    try stopUnqualifiedViewing("An exact selected row failed and a different fallback became selected during native qualification; the chosen source remains unqualified.")
                }
                XCTAssertFalse(settled.retryIDs.contains(settled.selectedID),
                               "A failed selected row cannot qualify native pictures")
                assertRetainedNativeViewingIdentity(changedPictures[paneIndex],
                    identifier: "native-measurement-pane-\(paneIndex + 1)",
                    message: "Source ownership receipt retains each qualified native picture")
            }
            assertNativeIdentity(changedPictures[1 - index], matches: pictures[1 - index],
                                 message: "Qualifying an actual alternate replaced its sibling's native owner")
            XCTAssertNotEqual(changedPictures[index]["attemptToken"] as? String,
                              pictures[index]["attemptToken"] as? String,
                              "A different selected source must prove its own native attempt, not the previous video's pixels")
            pictures = changedPictures
        }
        let audio = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-pane-audio-"))
        XCTAssertEqual(audio.count, 2)
        for control in audio.allElementsBoundByIndex {
            tap(control)
            XCTAssertEqual(control.value as? String, "Selected")
            XCTAssertEqual(audio.allElementsBoundByIndex.filter { $0.value as? String == "Selected" }.count, 1)
        }
        tap(app.buttons["viewing-swap"])
        XCTAssertEqual(Set(panes.allElementsBoundByIndex.map(\.identifier)), identities)
        for index in pictures.indices {
            assertRetainedNativeViewingIdentity(pictures[index], identifier: "native-measurement-pane-\(index + 1)",
                                               message: "Audio focus and Swap preserve both proven native owners")
        }
        guard let focusedPictures = qualifyCurrentViewingNativePair(timeout: 20,
            evidenceName: "Both native pictures after audio focus and Swap") else {
            try stopUnqualifiedViewing("Audio focus and Swap did not retain two advancing native pictures within the bounded observation; selected audio values alone are not proof.")
        }
        for index in pictures.indices {
            assertNativeIdentity(focusedPictures[index], matches: pictures[index],
                                 message: "Audio focus or Swap replaced a proven native item/attempt")
        }
        captureEvidence(surface: "Two native pictures and independent controls after audio focus and Swap")
        tap(app.buttons["viewing-minimize"])
        XCTAssertTrue(app.buttons["viewing-mini-expand"].waitForExistence(timeout: 5))
        try selectTab("tab-arena", surface: "Two native panes retained while browsing Matchday")
        tap(app.buttons["viewing-mini-expand"])
        XCTAssertTrue(waitUntil(timeout: 5) { panes.count == 2 })
        for index in pictures.indices {
            assertRetainedNativeViewingIdentity(pictures[index], identifier: "native-measurement-pane-\(index + 1)",
                                               message: "Compact browse/restore preserves both proven native owners")
        }
        guard let restoredPictures = qualifyCurrentViewingNativePair(timeout: 20,
            evidenceName: "Both native pictures after compact browse/restore") else {
            try stopUnqualifiedViewing("Compact browse/restore did not retain two advancing native pictures; preserved tokens alone are not video continuity.")
        }
        for index in pictures.indices {
            assertNativeIdentity(restoredPictures[index], matches: pictures[index],
                                 message: "Restoring Watch Two replaced a proven native item/attempt")
        }
        tap(app.buttons["viewing-return-one"])
        XCTAssertTrue(app.buttons["viewing-sources"].waitForExistence(timeout: 5))
        XCTAssertEqual(panes.count, 0)
        assertRetainedNativeViewingIdentity(pictures[0], identifier: "native-playback-measurement",
                                           message: "Return to one keeps the primary native owner")
        try closePlayer()
        capturedFocusedEnd = true
        navigationTimings.append("Strict current Watch Two: both real native panes proved ready rendered pixels and same-token media progression before controls and after each actual alternate. Audio focus, Swap, compact browsing, Return and Stop preserve owners. Physical automation is muted; audible exclusivity and continuous frame sampling are not claimed.")
    }

    /// Optional reviewed choices select only existing production buttons.
    /// Name must uniquely match one current row; ID is the real event suffix.
    /// Neither environment key creates fixtures or enables a source.
    func testPhysicalWatchTwoChangeMatchKeepsOtherPaneAndSupportsSearch() throws {
        executionTimeAllowance = 420
        try openRealPlayback()
        try waitForStartupUI(timeout: 65)
        tap(app.buttons["viewing-watch-two"])
        let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-second-match-"))
        XCTAssertTrue(waitUntil(timeout: 15) {
            candidates.count > 0 || self.app.staticTexts["No other broadcast yet"].exists
        })
        guard let second = candidates.allElementsBoundByIndex.first(where: \.isHittable) else {
            throw XCTSkip("The real current catalog has no second broadcast; no fixture was invented.")
        }
        tap(second)
        let panes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "viewing-pane-source-"))
        XCTAssertTrue(waitUntil(timeout: 45) { panes.count == 2 }, "A prepared second choice must open Watch Two")
        let identifiers = panes.allElementsBoundByIndex.map(\.identifier)
        let targetEventID = String(identifiers[1].dropFirst("viewing-pane-source-".count))
        let survivorID = identifiers[0]
        let survivor = readNativeMeasurement(identifier: "native-measurement-pane-1")
        let options = app.buttons["viewing-pane-options-\(targetEventID)"]
        try reveal(options)
        tap(options)
        let change = app.buttons["viewing-pane-change-\(targetEventID)"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        tap(change)
        // A global Home Search may remain mounted behind retained viewing.
        // Raw firstMatch/exists can select that hidden field, not this sheet.
        var activeField: XCUIElement?
        XCTAssertTrue(waitUntil(timeout: 5) {
            activeField = self.app.searchFields.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            return activeField != nil
        }, "Changing a match must expose its actual searchable picker")
        let field = try XCTUnwrap(activeField)
        XCTAssertTrue(waitUntil(timeout: 15) {
            candidates.count > 0 || self.app.staticTexts["No other broadcast yet"].exists
        })
        guard candidates.count > 0 else {
            tap(app.buttons["Done"].firstMatch)
            try closePlayer()
            throw XCTSkip("No third real broadcast is currently eligible for replacement; existing controls were exercised.")
        }
        tap(field)
        field.typeText("zzfixturedoesnotexist")
        XCTAssertEqual(field.value as? String, "zzfixturedoesnotexist")
        XCTAssertTrue(app.staticTexts["No matching broadcast"].waitForExistence(timeout: 5))
        var activeCancel: XCUIElement?
        XCTAssertTrue(waitUntil(timeout: 3) {
            activeCancel = self.app.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
                .allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            return activeCancel != nil
        })
        let cancelSearch = try XCTUnwrap(activeCancel)
        tap(cancelSearch)
        XCTAssertTrue(waitUntil(timeout: 5) { candidates.count > 0 })
        let next = try XCTUnwrap(candidates.allElementsBoundByIndex.first(where: \.isHittable))
        let nextID = String(next.identifier.dropFirst("viewing-second-match-".count))
        tap(next)
        let replacement = app.buttons["viewing-pane-source-\(nextID)"]
        XCTAssertTrue(replacement.waitForExistence(timeout: 45))
        XCTAssertTrue(app.buttons[survivorID].exists, "The other pane must remain mounted")
        XCTAssertFalse(app.buttons[identifiers[1]].exists, "Only the selected pane is replaced")
        if let survivor {
            assertRetainedNativeViewingIdentity(survivor, identifier: "native-measurement-pane-1",
                                               message: "Changing the other match retains the native survivor")
        }
        navigationTimings.append("Change match and Search controls checked; survivor native identity receipt=\(survivor != nil). Missing/Web receipts remain unknown. A replacement source row is not decoded-video or audible-audio proof; the strict two-native-picture gate is separate.")
        captureEvidence(surface: "Watch Two actual Change match, Search and retained other pane")
        try closePlayer()
        capturedFocusedEnd = true
    }

    private func reviewedRealViewingSecondCandidate(in candidates: XCUIElementQuery) throws -> XCUIElement? {
        let environment = ProcessInfo.processInfo.environment
        let name = environment["FOTTY_VIEWING_SECOND_MATCH_NAME"]
        let id = environment["FOTTY_VIEWING_SECOND_MATCH_ID"]
        for (key, value, limit) in [("FOTTY_VIEWING_SECOND_MATCH_NAME", name, 160),
                                    ("FOTTY_VIEWING_SECOND_MATCH_ID", id, 200)] {
            if let value {
                guard !value.isEmpty, value.count <= limit,
                      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw NSError(domain: "Fotty.PhysicalViewingConfiguration", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "\(key) must identify a bounded, freshly reviewed real row."])
                }
            }
        }
        for _ in 0..<6 {
            let matches = candidates.allElementsBoundByIndex.filter { row in
                (id.map { row.identifier == "viewing-second-match-\($0)" } ?? true)
                    && (name.map { row.label.localizedCaseInsensitiveContains($0) } ?? true)
            }
            if name == nil && id == nil { return matches.first { $0.isHittable } }
            guard matches.count <= 1 else {
                throw NSError(domain: "Fotty.PhysicalViewingConfiguration", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "The reviewed second-match name is ambiguous; provide its actual event ID."])
            }
            if let match = matches.first, match.isHittable { return match }
            let scroll = visibleContentScroll
            guard scroll.exists && scroll.isHittable else { break }
            scroll.swipeUp()
        }
        return nil
    }

    private func qualifyCurrentViewingNativePair(timeout: TimeInterval,
                                                evidenceName: String) -> [[String: Any]]? {
        let hooks = (1...2).map { app.descendants(matching: .any)["native-measurement-pane-\($0)"].firstMatch }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        var previous: [[String: Any]]?
        var sampleCount = 0
        var nextSample = Date.distantPast
        while Date() < deadline {
            let receipts = hooks.map { readNativeMeasurement(in: $0) }
            let pictures = receipts.compactMap { $0 }
            let ready = pictures.count == 2 && pictures.allSatisfy {
                $0["readyForDisplay"] as? Bool == true
                    && ($0["renderedPixelWidth"] as? Double ?? 0) > 0
                    && ($0["renderedPixelHeight"] as? Double ?? 0) > 0
                    && ($0["currentTimeSeconds"] as? Double)?.isFinite == true
            }
            if Date() >= nextSample {
                if ready {
                    for index in pictures.indices {
                        attachNativeMeasurementScalars(pictures[index],
                            name: "\(evidenceName), logical pane \(index + 1), sample \(sampleCount + 1)")
                    }
                    if let previous {
                        for index in pictures.indices {
                            guard pictures[index]["itemToken"] as? String == previous[index]["itemToken"] as? String,
                                  pictures[index]["attemptToken"] as? String == previous[index]["attemptToken"] as? String,
                                  let currentTime = pictures[index]["currentTimeSeconds"] as? Double,
                                  let earlierTime = previous[index]["currentTimeSeconds"] as? Double,
                                  currentTime > earlierTime + 0.1 else { return nil }
                        }
                    }
                    sampleCount += 1
                    if sampleCount == 3 { return pictures }
                    previous = pictures
                    nextSample = Date().addingTimeInterval(5)
                } else if previous != nil {
                    navigationTimings.append("\(evidenceName): a previously ready native pane lost its ready/pixel receipt at a separated sample; pair remains unqualified.")
                    return nil
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        navigationTimings.append("\(evidenceName): no three-sample native pair receipt within \(Int(timeout)) seconds; absent/Web receipts remain unknown.")
        return nil
    }

    private func stopUnqualifiedViewing(_ reason: String) throws -> Never {
        captureEvidence(surface: "UNQUALIFIED current viewing playback")
        navigationTimings.append("UNQUALIFIED: \(reason)")
        let lookup = app.descendants(matching: .any)["viewing-resolution"].firstMatch
        let cancel = app.buttons["Cancel"].firstMatch
        if lookup.exists && cancel.isHittable { tap(cancel) }
        let unavailable = app.alerts["Broadcast not ready"]
        if unavailable.exists { tap(unavailable.buttons["OK"]) }
        try closePlayer()
        capturedFocusedEnd = true
        throw XCTSkip(reason)
    }

    /// Never tap the provider video to discover controls: a surface tap can
    /// itself pause/restart the provider. Native mini transport is canonical;
    /// the web route uses only its already exposed UIKit transport button.
    private func pauseViewingThroughCanonicalControl(usesNativeTransport: Bool) throws {
        if usesNativeTransport {
            let pause = app.buttons.matching(NSPredicate(format: "label == %@", "Pause"))
                .allElementsBoundByIndex.first { $0.isHittable }
            if let pause { tap(pause) }
            else {
                tap(app.buttons["viewing-minimize"])
                let native = app.buttons["viewing-mini-transport"]
                XCTAssertTrue(native.waitForExistence(timeout: 5), "A native single pane must expose its compact transport")
                XCTAssertEqual(native.label, "Pause broadcast", "The initial native playback did not offer explicit Pause")
                tap(native)
                XCTAssertTrue(waitUntil(timeout: 5) { native.label == "Resume broadcast" })
                tap(app.buttons["viewing-mini-expand"])
                XCTAssertTrue(app.buttons["viewing-sources"].waitForExistence(timeout: 5))
            }
        } else {
            let web = app.buttons["web-play-pause"]
            guard web.exists, web.isHittable, web.label == "Pause broadcast" else {
                captureEvidence(surface: "Canonical web Pause is unavailable; no provider-surface tap substituted")
                try closePlayer()
                throw XCTSkip("No already exposed canonical web Pause control was available; deliberate-pause continuity is unqualified.")
            }
            tap(web)
            XCTAssertTrue(waitUntil(timeout: 5) { web.label == "Play broadcast" })
        }
    }

    private func assertViewingPause(usesNativeTransport: Bool) {
        if usesNativeTransport {
            XCTAssertTrue(waitUntil(timeout: 5) {
                guard let receipt = self.readNativeMeasurement(identifier: "native-playback-measurement") else { return false }
                return (receipt["rate"] as? Double) == 0
                    && (receipt["timeControlStatus"] as? Int) == 0
                    && (self.app.buttons.matching(NSPredicate(format: "label == %@", "Play")).firstMatch.exists
                        || self.app.staticTexts["Paused"].exists)
            }, "The native pane lost its deliberate paused transport/visible intent")
        } else {
            XCTAssertTrue(waitUntil(timeout: 5) {
                let transport = self.app.buttons["web-play-pause"]
                return transport.exists && transport.label == "Play broadcast"
            }, "Restoration lost the canonical web paused intent")
        }
    }

    private func exercisePausedViewingFocusRotation(before: [String: Any]?, usesNativeTransport: Bool) throws {
        let original = XCUIDevice.shared.orientation
        let exit = app.buttons["viewing-exit-focus"]
        let originalFrame = try XCTUnwrap(positiveAppWindow(containing: exit),
                                          "No current positive app window contains the actual Focus exit").frame
        let restore = original.isPortrait || original.isLandscape
            ? original : (originalFrame.width > originalFrame.height ? .landscapeLeft : .portrait)
        defer { XCUIDevice.shared.orientation = restore }
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(waitUntil(timeout: 8) {
                guard let window = self.positiveAppWindow(containing: exit) else { return false }
                let frame = window.frame
                let matches = orientation.isPortrait ? frame.height > frame.width : frame.width > frame.height
                return matches && exit.isHittable
            }, "The actual focused window did not reflow to \(name) with an accessible exit")
            XCTAssertEqual(app.state, .runningForeground)
            assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                               message: "Paused Focus \(name) rotation")
            assertViewingPause(usesNativeTransport: usesNativeTransport)
            captureEvidence(surface: "Actual paused Focus \(name) layout")
        }
    }

    private func assertRetainedNativeViewingIdentity(_ before: [String: Any]?, identifier: String,
                                                    message: String) {
        guard let before else { return }
        guard let after = readNativeMeasurement(identifier: identifier) else {
            XCTFail("\(message): the previously available native identity receipt disappeared")
            return
        }
        XCTAssertEqual(before["itemToken"] as? String, after["itemToken"] as? String, "\(message): native item changed")
        XCTAssertEqual(before["attemptToken"] as? String, after["attemptToken"] as? String, "\(message): source attempt changed")
        attachNativeMeasurementScalars(after, name: message)
    }

    /// Source numbers identify stable rows within one prepared pane; neither
    /// provider labels nor the legacy “Source 1/2” vocabulary identify variants.
    private struct ViewingSourceChoiceEvidence {
        let selectedID: String
        let retryIDs: Set<String>
    }

    private func currentViewingSourceEvidence(in pane: XCUIElement) throws -> ViewingSourceChoiceEvidence {
        try reveal(pane)
        tap(pane)
        XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 5), "The current pane lost its real source picker")
        let rows = sourceRows.allElementsBoundByIndex
        let selected = rows.filter { $0.isSelected }
        XCTAssertEqual(selected.count, 1, "Each current pane must have one selected source row")
        let identifier = try XCTUnwrap(selected.first?.identifier)
        let retries = Set(rows.filter { $0.label.hasSuffix(", Try again") }.map(\.identifier))
        let bounded = rows.prefix(40).map { "\($0.identifier): selected=\($0.isSelected), retry=\(retries.contains($0.identifier))" }
        let receipt = XCTAttachment(string: "Pane=\(pane.identifier); time=\(Date().timeIntervalSince1970)\n" + bounded.joined(separator: "\n"))
        receipt.name = "Independent pane selected-row and retry evidence"
        receipt.lifetime = .keepAlways
        add(receipt)
        try closeSourceSheetIfPresent()
        return .init(selectedID: identifier, retryIDs: retries)
    }

    private func switchCurrentViewingPaneSource(_ pane: XCUIElement, measurementIdentifier: String,
                                               preserving sibling: XCUIElement,
                                               siblingMeasurementIdentifier: String) throws -> Bool {
        let siblingSource = try currentViewingSourceEvidence(in: sibling)
        let siblingBefore = readNativeMeasurement(identifier: siblingMeasurementIdentifier)
        let current = try currentViewingSourceEvidence(in: pane)
        let before = readNativeMeasurement(identifier: measurementIdentifier)
        try reveal(pane)
        tap(pane)
        XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 5))
        guard let alternate = sourceRows.allElementsBoundByIndex.first(where: { !$0.isSelected && $0.isEnabled }) else {
            captureEvidence(surface: "Current pane has no real alternate source; selection not invented")
            try closeSourceSheetIfPresent()
            let siblingAfter = try currentViewingSourceEvidence(in: sibling)
            XCTAssertEqual(siblingAfter.selectedID, siblingSource.selectedID)
            assertRetainedNativeViewingIdentity(siblingBefore, identifier: siblingMeasurementIdentifier,
                                               message: "Unavailable alternate must not change its sibling")
            return false
        }
        let chosenID = alternate.identifier
        XCTAssertNotEqual(chosenID, current.selectedID)
        try reveal(alternate)
        tap(alternate)
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["Close broadcast sources"].exists })
        try waitForStartupUI(timeout: 65)
        let selected = try currentViewingSourceEvidence(in: pane)
        let siblingAfter = try currentViewingSourceEvidence(in: sibling)
        var sourceChoiceQualified = true
        if selected.selectedID != chosenID {
            XCTAssertTrue(selected.retryIDs.contains(chosenID),
                          "The requested alternate lost selection without failed-row/fallback evidence")
            navigationTimings.append("Requested alternate did not qualify: exact requested row is now marked Try again with a distinct selected fallback. Not chosen-source success.")
            sourceChoiceQualified = false
        }
        if siblingAfter.selectedID != siblingSource.selectedID {
            XCTAssertTrue(!siblingSource.retryIDs.contains(siblingSource.selectedID)
                          && siblingAfter.retryIDs.contains(siblingSource.selectedID),
                          "Changing one current pane changed its sibling without new failed-row/fallback evidence")
            navigationTimings.append("Sibling independence unqualified: its exact prior healthy row is now unselected and marked Try again with a distinct selected fallback. This is recovery evidence, not proof the requested source switch caused it.")
            sourceChoiceQualified = false
        }
        if !sourceChoiceQualified {
            captureEvidence(surface: "Source-choice qualification incomplete with bounded retry/fallback receipts")
            return false
        }
        assertRetainedNativeViewingIdentity(siblingBefore, identifier: siblingMeasurementIdentifier,
                                           message: "Changing a current pane source preserves its sibling")
        let after = readNativeMeasurement(identifier: measurementIdentifier)
        if let before, let after {
            XCTAssertNotEqual(before["attemptToken"] as? String, after["attemptToken"] as? String,
                              "An explicit different native source did not begin its own attempt")
        }
        captureEvidence(surface: "Actual current-pane alternate selected; sibling row and available native identity preserved")
        navigationTimings.append("Current pane alternate: row \(current.selectedID) → \(chosenID); sibling selected row unchanged. Native sibling receipt=\(siblingBefore != nil), switched native receipt=\(before != nil && after != nil). Unknown/Web receipts are not decoded-video proof.")
        return true
    }

    private func readNativeMeasurement(identifier: String) -> [String: Any]? {
        let hook = app.descendants(matching: .any)[identifier].firstMatch
        return readNativeMeasurement(in: hook)
    }

    private func readNativeMeasurement(in hook: XCUIElement) -> [String: Any]? {
        guard hook.exists, let value = hook.value as? String,
              let data = value.data(using: .utf8), data.count <= 4_096,
              let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = receipt["itemToken"] as? String, UUID(uuidString: item) != nil,
              let attempt = receipt["attemptToken"] as? String, UUID(uuidString: attempt) != nil else { return nil }
        return receipt
    }

    /// The gate supplies public teams from a freshly reviewed real CS catalog;
    /// it never installs an add-on, enables a source, or injects a fixture.
    func testPhysicalProductionCommunitySourceSelectionAndControl() throws {
        _ = try qualifyReviewedCommunitySource(leavePlayerOpen: false)
    }

    /// Discovery acceptance is separate from decoded playback: exercise the
    /// real suffixed catalog row, not a synthetic fixture or its plain duplicate.
    func testPhysicalProductionCommunitySourceLegalNameMatching() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let query = environment["FOTTY_CS_TEST_QUERY"], !query.isEmpty, query.count <= 80,
              let home = environment["FOTTY_CS_TEST_HOME"], !home.isEmpty, home.count <= 80,
              let away = environment["FOTTY_CS_TEST_AWAY"], !away.isEmpty, away.count <= 80 else {
            throw XCTSkip("A freshly reviewed real CS fixture is required for legal-name matching.")
        }
        try openSearch()
        try replaceSearchText(with: query)
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.app.searchFields.firstMatch.value as? String == query
                && !self.app.staticTexts["Searching…"].exists
        })
        let watch = searchSurface.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@ AND label CONTAINS[c] %@",
            "Watch", home, away)).firstMatch
        // A cold production launch can still be collecting provider metadata.
        // Keep that bounded wait separate from native playback qualification.
        guard watch.waitForExistence(timeout: 40) else {
            throw XCTSkip("The reviewed legal-name fixture is absent from Fotty; another row cannot qualify this regression.")
        }
        try dismissSearchKeyboard(preservingQuery: query)
        try reveal(watch)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, query)
        let selected = XCTAttachment(string: "Real catalog Watch row: \(watch.label). Discovery-only gate; no fixture injection, module enablement or decoded-playback claim.")
        selected.name = "CS legal-name fixture selection"
        selected.lifetime = .keepAlways
        add(selected)
        tap(watch)
        XCTAssertTrue(player.waitForExistence(timeout: 40))
        try revealPlayerChrome()
        let expectedPicker = currentSingleSourcePicker
        XCTAssertTrue(expectedPicker.waitForExistence(timeout: 3) && expectedPicker.isHittable,
                      "The verified legal-name fixture lost its expected source alternatives; this is a regression, not an optional-source skip")
        try openSources()
        let choices = sourceRows.matching(NSPredicate(format: "label MATCHES %@", "^CS[1-6], .+"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8),
                      "The reviewed suffixed fixture lost every CS option despite a verified plain-name upstream match")
        let labels = choices.allElementsBoundByIndex.map { String($0.label.split(separator: ",", maxSplits: 1)[0]) }
        XCTAssertFalse(labels.isEmpty)
        XCTAssertLessThanOrEqual(labels.count, 6)
        XCTAssertEqual(Set(labels).count, labels.count)
        captureEvidence(surface: "Real suffixed football fixture with admitted CS options")
        try closePlayer()
    }

    private struct QualifiedCommunitySource {
        let identifier: String
        let family: String
        let nativeMeasurement: [String: Any]
    }

    private var hasReviewedCommunitySourceConfiguration: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["FOTTY_CS_TEST_QUERY", "FOTTY_CS_TEST_HOME", "FOTTY_CS_TEST_AWAY"]
            .contains { environment[$0] != nil }
    }

    /// The PiP gate may reuse the same reviewed, actually qualified CS setup,
    /// rather than substituting an arbitrary channel or assuming a CS number.
    private func qualifyReviewedCommunitySource(leavePlayerOpen: Bool,
                                                attemptTimeout: TimeInterval = 150) throws -> QualifiedCommunitySource {
        let environment = ProcessInfo.processInfo.environment
        guard let query = environment["FOTTY_CS_TEST_QUERY"], !query.isEmpty, query.count <= 80,
              let home = environment["FOTTY_CS_TEST_HOME"], !home.isEmpty, home.count <= 80,
              let away = environment["FOTTY_CS_TEST_AWAY"], !away.isEmpty, away.count <= 80 else {
            throw XCTSkip("A freshly reviewed public CS match is required for this bounded real-source check.")
        }
        let requiredFamily = environment["FOTTY_CS_REQUIRED_FAMILY"]
        if let requiredFamily {
            _ = try XCTUnwrap(requiredFamily.range(of: "^CS[1-6]$", options: .regularExpression),
                              "The optional exact-source gate accepts one bounded CS family only")
        }
        // Playback qualification can use the ordinary Home route for the
        // exact reviewed pair. The separate legal-name discovery regression
        // still requires Search. This avoids letting a Search/keyboard setup
        // failure stand in for a CS playback or PiP result.
        let useHome = environment["FOTTY_CS_TEST_USE_HOME"] == "1"
        if !useHome {
            try openSearch()
            try replaceSearchText(with: query)
            XCTAssertTrue(waitUntil(timeout: 8) {
                self.app.searchFields.firstMatch.value as? String == query
                    && !self.app.staticTexts["Searching…"].exists
            })
        }
        let watchScope: XCUIElement = useHome ? try XCTUnwrap(app) : searchSurface
        let watchPredicate = useHome
            ? NSPredicate(format: "label == %@", "Watch \(home) vs \(away)")
            : NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@ AND label CONTAINS[c] %@",
                          "Watch", home, away)
        let watch = watchScope.buttons.matching(watchPredicate).firstMatch
        guard watch.waitForExistence(timeout: 10) else {
            throw XCTSkip("The reviewed CS fixture is not currently watchable in Fotty's real catalog; no fixture or channel substitution is allowed.")
        }
        // On the physical iPad, swiping a partially keyboard-covered Search
        // scroll view corrupted the query instead of revealing this control.
        // Dismiss the native keyboard first; that harness failure cannot count
        // as source-discovery or playback evidence.
        if !useHome { try dismissSearchKeyboard(preservingQuery: query) }
        for _ in 0..<4 where !watch.isHittable {
            if !useHome { XCTAssertEqual(app.searchFields.firstMatch.value as? String, query) }
            let scroll = visibleContentScroll
            XCTAssertTrue(scroll.exists && scroll.isHittable)
            scroll.swipeUp()
        }
        if !useHome { XCTAssertEqual(app.searchFields.firstMatch.value as? String, query) }
        XCTAssertTrue(watch.isHittable, "The exact reviewed Watch control is covered")
        navigationTimings.append("CS qualification route: \(useHome ? "Home" : "Search"); real Watch row: \(watch.label).")
        tap(watch)
        XCTAssertTrue(player.waitForExistence(timeout: 40))
        try revealPlayerChrome()
        let expectedPicker = currentSingleSourcePicker
        XCTAssertTrue(expectedPicker.waitForExistence(timeout: 3) && expectedPicker.isHittable,
                      "The reviewed CS fixture lost its expected source alternatives; this is not an optional-source skip")
        try openSources()
        let csChoices = sourceRows.matching(NSPredicate(format: "label MATCHES %@", "^CS[0-9]+, .+"))
        XCTAssertTrue(csChoices.firstMatch.waitForExistence(timeout: 8), "An independently reviewed exact CS fixture returned eligible streams, but no CS choice appeared")
        let availableChoices = csChoices.allElementsBoundByIndex.map {
            (identifier: $0.identifier, family: String($0.label.split(separator: ",", maxSplits: 1)[0]), selected: $0.isSelected)
        }
        var candidateIDs: Set<String> = []
        // Qualify the actual current CS owner before replacing it with another
        // upstream attempt. A selected fallback is proved under its own family,
        // never counted as success for the failed source that preceded it.
        // Selection alone is not health: the same row/item/attempt and native
        // progress checks below, and the PiP identity fences, still apply.
        let orderedChoices = availableChoices.filter { $0.selected }
            + availableChoices.filter { !$0.selected }
        if let requiredFamily {
            _ = try XCTUnwrap(availableChoices.first { $0.family == requiredFamily },
                              "The freshly reviewed exact CS source is missing from this real fixture")
        }
        let candidates = orderedChoices.filter { requiredFamily == nil || $0.family == requiredFamily }
            .filter { candidateIDs.insert($0.identifier).inserted }.prefix(3)
        captureEvidence(surface: "Production source picker with real CS alternatives")

        // Selection may legitimately change after an explicit source failure.
        // Only the failed row plus a distinct selected fallback establishes that
        // case; arbitrary ownership loss must still fail this gate.
        func selectionEvidence(for identifier: String, family: String) -> (selected: Bool, failed: Bool, fallback: Bool) {
            let row = sourceRows.matching(identifier: identifier).firstMatch
            let matchesFamily = row.exists && row.label.hasPrefix("\(family), ")
            let selected = matchesFamily && row.isSelected
            let failed = matchesFamily && row.label.hasSuffix(", Try again")
            let fallback = sourceRows.allElementsBoundByIndex.contains {
                $0.identifier != identifier && $0.isSelected
            }
            return (selected, failed, fallback)
        }

        let attemptDeadline = Date().addingTimeInterval(attemptTimeout)
        var qualified: QualifiedCommunitySource?
        for candidate in candidates {
            guard Date() < attemptDeadline else { break }
            let cs = sourceRows.matching(identifier: candidate.identifier).firstMatch
            XCTAssertTrue(cs.exists && cs.label.hasPrefix("\(candidate.family), "),
                          "The reviewed CS row changed identity within this player session")
            for _ in 0..<6 where !cs.isHittable {
                let scroll = app.scrollViews.allElementsBoundByIndex.filter { $0.isHittable }
                    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
                guard let scroll else { break }
                scroll.swipeUp()
            }
            if cs.isSelected && !cs.label.hasSuffix(", Try again") { try closeSourceSheetIfPresent() }
            else { tap(cs) }
            XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["Close broadcast sources"].exists })

            try openSources(requirePreviouslyObservedPicker: true)
            let immediate = selectionEvidence(for: candidate.identifier, family: candidate.family)
            XCTAssertTrue(immediate.selected || (immediate.failed && immediate.fallback),
                          "The requested CS source was not selected and no failed-row/fallback evidence explains the change")
            if !immediate.selected {
                navigationTimings.append("\(candidate.family): failed row and distinct selected fallback observed immediately; CS playback unqualified.")
                captureEvidence(surface: "Production \(candidate.family) failure with responsive source controls")
                continue
            }
            try closeSourceSheetIfPresent()
            let timeout = min(65, max(0, attemptDeadline.timeIntervalSinceNow))
            let decodedMeasurement = nativeLayerAndMediaProgressMeasurement(timeout: timeout,
                evidenceName: "\(candidate.family) qualification window")
            try openSources(requirePreviouslyObservedPicker: true)
            let settled = selectionEvidence(for: candidate.identifier, family: candidate.family)
            XCTAssertTrue(settled.selected || (settled.failed && settled.fallback),
                          "The requested CS source lost selection without failed-row/fallback evidence")
            captureEvidence(surface: "Production \(candidate.family) selection and responsive source controls")
            if settled.selected && !settled.failed, let decodedMeasurement {
                qualified = QualifiedCommunitySource(identifier: candidate.identifier,
                                                     family: candidate.family,
                                                     nativeMeasurement: decodedMeasurement)
                break
            }
            if !settled.selected {
                navigationTimings.append("\(candidate.family): failed row and distinct selected fallback observed; fallback progress is not CS success.")
            } else {
                navigationTimings.append("\(candidate.family): selected source did not prove stable native progress within its bounded attempt; CS playback unqualified.")
            }
        }
        try closeSourceSheetIfPresent()
        guard let qualified else {
            try closePlayer()
            throw XCTSkip("Real CS discovery and responsive source controls were exercised, but no attempted CS variant proved same-selected-source native media-time progress within the bounded gate. Evidenced source failure/failover is not CS playback success.")
        }
        navigationTimings.append("\(qualified.family) remained selected; ready native layer and same-item media-time progress observed; muted automation does not prove sound.")
        if leavePlayerOpen {
            endSurface = "Production qualified real CS native player"
        } else {
            try closePlayer()
            endSurface = "Home after real CS playback and source controls"
        }
        return qualified
    }

    /// Recheck actual source ownership and the exact proven native identity
    /// before PiP. Only an explicitly failed reviewed row plus a selected
    /// fallback explains an unqualified setup; arbitrary ownership loss fails.
    private func verifyQualifiedCommunitySource(_ qualified: QualifiedCommunitySource) throws {
        try openSources(requirePreviouslyObservedPicker: true)
        let row = sourceRows.matching(identifier: qualified.identifier).firstMatch
        XCTAssertTrue(row.exists && row.label.hasPrefix("\(qualified.family), "),
                      "The qualified CS row changed identity before PiP")
        let failed = row.label.hasSuffix(", Try again")
        let fallback = sourceRows.allElementsBoundByIndex.contains {
            $0.identifier != qualified.identifier && $0.isSelected
        }
        if failed && !row.isSelected && fallback {
            navigationTimings.append("\(qualified.family): explicit failed row and distinct selected fallback before PiP; CS PiP remains unqualified.")
            try closeSourceSheetIfPresent()
            try closePlayer()
            throw XCTSkip("The previously qualified real CS source failed before PiP; fallback playback is not CS PiP qualification.")
        }
        XCTAssertTrue(row.isSelected && !failed,
                      "The qualified CS source lost selection before PiP without explicit failed-row/fallback evidence")
        try closeSourceSheetIfPresent()
        let current = try readNativeMeasurement()
        assertNativeIdentity(current, matches: qualified.nativeMeasurement,
                             message: "The qualified CS native identity changed before PiP")
    }

    private func assertNativeIdentity(_ current: [String: Any], matches expected: [String: Any],
                                      message: String) {
        for key in ["itemToken", "attemptToken"] {
            XCTAssertEqual(current[key] as? String, expected[key] as? String, message)
        }
    }

    /// The presentation gate is transport-independent. Web playback can prove
    /// real layout/touch behavior, never AVKit identity or decoded-frame health.
    func testPhysicalIPadVideoFirstPresentationOnRealHomeSource() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This video-first acceptance gate is for Jet iPad only.")
        }
        let original = XCUIDevice.shared.orientation
        defer {
            let done = app.buttons["viewing-details-done"]
            if done.exists && done.isHittable { tap(done) }
            try? closeSourceSheetIfPresent()
            if player.exists { try? closePlayer() }
            if original.isPortrait || original.isLandscape { XCUIDevice.shared.orientation = original }
        }
        try openVideoFirstHomePlayback()
        try waitForStartupUI(timeout: 40)
        let before = readNativeMeasurement(identifier: "native-playback-measurement")
        captureEvidence(surface: "Video-first real source before presentation changes")
        try exerciseVideoFirstRotation(before: before, preservesPause: false, usesNativeTransport: before != nil)
        tap(app.buttons["viewing-details"])
        let done = app.buttons["viewing-details-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["viewing-companion"].firstMatch.exists)
        captureEvidence(surface: "Video-first on-demand Details without permanent rail")
        tap(done)
        XCTAssertTrue(waitUntil(timeout: 5) { !done.exists })
        try openSources(requirePreviouslyObservedPicker: true)
        let selected = sourceRows.allElementsBoundByIndex.first { $0.isSelected }?.identifier
        XCTAssertNotNil(selected, "The real source picker must identify its current source")
        captureEvidence(surface: "Video-first existing match source picker")
        try closeSourceSheetIfPresent()
        try openSources(requirePreviouslyObservedPicker: true)
        if let selected { XCTAssertTrue(sourceRows.matching(identifier: selected).firstMatch.isSelected) }
        try closeSourceSheetIfPresent()
        assertRetainedNativeViewingIdentity(before, identifier: "native-playback-measurement",
                                           message: "Video-first presentation and picker dismissal")
        XCTAssertTrue(app.buttons["viewing-details"].isHittable)
        captureEvidence(surface: "Video-first real source after presentation changes")
        navigationTimings.append("Transport-independent Home playback presentation: portrait/landscape, on-demand Details/Done, Sources open/cancel/reopen preserves selected source. Missing Web native receipts are unknown; no AVKit/decoded-frame/audio/continuous-Web-clock claim.")
        try closePlayer()
        capturedFocusedEnd = true
    }

    /// Real Home delivery and public native controls only. Sheets and rotation
    /// must retain one owner; this does not qualify a provider or a PiP route.
    func testPhysicalIPadVideoFirstDetailsSourcesAndNativeControlsRetainOwner() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This video-first acceptance gate is for Jet iPad only.")
        }
        executionTimeAllowance = 240
        let deadline = Date().addingTimeInterval(210)
        let original = XCUIDevice.shared.orientation
        let window = app.windows.firstMatch.frame
        let restore = original.isPortrait || original.isLandscape
            ? original : (window.width > window.height ? .landscapeLeft : .portrait)
        var baseline: [String: Any]?
        defer {
            let done = app.buttons["viewing-details-done"]
            if done.exists && done.isHittable { tap(done) }
            if app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch.exists,
               let baseline { try? exitNativeFullscreen(expected: baseline) }
            try? closeSourceSheetIfPresent()
            if player.exists { try? closePlayer() }
            let cancel = app.buttons["Cancel"].firstMatch
            if app.descendants(matching: .any)["stream-resolution-panel"].firstMatch.exists && cancel.isHittable { tap(cancel) }
            XCUIDevice.shared.orientation = restore
        }

        try openVideoFirstHomePlayback()

        var ready = nativeLayerAndMediaProgressMeasurement(timeout: 25, evidenceName: "Video-first initial real source")
        var attempted: Set<String> = []
        for _ in 0..<2 where ready == nil && deadline.timeIntervalSinceNow > 90 {
            try openSources()
            for row in sourceRows.allElementsBoundByIndex where row.isSelected { attempted.insert(row.identifier) }
            guard let alternate = sourceRows.allElementsBoundByIndex.first(where: {
                !$0.isSelected && $0.isEnabled && $0.isHittable && !attempted.contains($0.identifier)
            }) else { try closeSourceSheetIfPresent(); break }
            attempted.insert(alternate.identifier)
            tap(alternate)
            ready = nativeLayerAndMediaProgressMeasurement(timeout: min(25, max(0, deadline.timeIntervalSinceNow - 90)),
                evidenceName: "Video-first bounded real alternative")
        }
        guard ready != nil else {
            captureEvidence(surface: "Video-first native gate unavailable after bounded real sources")
            throw XCTSkip("No ready advancing native delivery qualified after the real Home source and at most two real alternatives. This is not a source-qualification or native-controls pass.")
        }
        let owner = try strictNativeOwner(identifier: "native-playback-measurement")
        baseline = owner
        try exerciseVideoFirstRotation(before: owner, preservesPause: false, usesNativeTransport: true)

        tap(app.buttons["viewing-details"])
        let done = app.buttons["viewing-details-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["viewing-companion"].firstMatch.exists)
        captureEvidence(surface: "Video-first on-demand Details")
        tap(done)
        XCTAssertTrue(waitUntil(timeout: 5) { !done.exists })
        XCTAssertFalse(app.descendants(matching: .any)["viewing-companion"].firstMatch.exists)
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"), expected: owner,
                               stage: "Details Done keeps the real native owner")
        try openSources(requirePreviouslyObservedPicker: true)
        try closeSourceSheetIfPresent()
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"), expected: owner,
                               stage: "Sources cancel keeps the real native owner")
        guard deadline.timeIntervalSinceNow > 55 else {
            captureEvidence(surface: "Video-first native-controls time budget exhausted")
            throw XCTSkip("Layout/sheet checks ran, but the bounded gate has insufficient time for native controls; no full acceptance pass.")
        }
        try enterNativeFullscreen(expected: owner)
        try tapActualNativeFullscreenControl(.pause, expected: owner)
        try assertNativeFullscreenPaused(expected: owner)
        try tapActualNativeFullscreenControl(.play, expected: owner)
        try requireNativeFullscreenProgress(expected: owner, stage: "Video-first actual AVKit Resume")
        try exitNativeFullscreen(expected: owner)
        let resumed = try XCTUnwrap(nativeLayerAndMediaProgressMeasurement(timeout: 8),
            "Native Done must restore the same ready advancing inline owner")
        assertSharedNativeOwner(resumed, expected: owner, stage: "Video-first actual AVKit Done returns inline")
        navigationTimings.append("Video-first iPad: real Home Watch, bounded native setup, portrait/landscape, Details/Done, Sources cancel and actual AVKit Pause/Resume/Done preserve player/item/attempt. Not source qualification, PiP, audible playback or a sustained decoded-frame soak.")
        try closePlayer()
        capturedFocusedEnd = true
    }

    /// Focused continuation of the accepted video-first presentation gate.
    /// Select only an observed existing picker row; never inject media, enable
    /// a provider, or count a fallback's progress as the requested delivery.
    func testPhysicalIPadVideoFirstNativeFullscreenPausedReturnAndResume() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This native fullscreen gate is for Jet iPad only.")
        }
        guard let label = ProcessInfo.processInfo.environment["FOTTY_VIDEO_FIRST_NATIVE_SOURCE_LABEL"],
              !label.isEmpty, label.count <= 60,
              !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw XCTSkip("Name an observed existing source label for this focused native gate.")
        }
        executionTimeAllowance = 420
        var baseline: [String: Any]?
        defer {
            if app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch.exists,
               let baseline { try? exitNativeFullscreen(expected: baseline) }
            try? closeSourceSheetIfPresent()
            if player.exists { try? closePlayer() }
        }
        try openVideoFirstHomePlayback()
        try openSources(requirePreviouslyObservedPicker: true)
        let candidate = sourceRows.matching(NSPredicate(format: "label BEGINSWITH %@", "\(label), ")).firstMatch
        guard candidate.waitForExistence(timeout: 8) else {
            captureEvidence(surface: "Requested existing native candidate is not listed")
            throw XCTSkip("The observed source is no longer listed on this real Home match; no replacement was injected.")
        }
        let identifier = candidate.identifier
        for _ in 0..<6 where !candidate.isHittable {
            guard let scroll = app.scrollViews.allElementsBoundByIndex.filter({ $0.isHittable })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { break }
            scroll.swipeUp()
        }
        if candidate.isSelected && !candidate.label.hasSuffix(", Try again") { try closeSourceSheetIfPresent() }
        else { tap(candidate) }
        // Preparation/validation precedes the native startup budget. Give the
        // existing source one bounded minute instead of abandoning it at25s.
        let ready = nativeLayerAndMediaProgressMeasurement(timeout: 60,
            evidenceName: "Observed existing \(label) native fullscreen setup")
        try openSources(requirePreviouslyObservedPicker: true)
        let selected = sourceRows.matching(identifier: identifier).firstMatch
        let isRequestedOwner = selected.exists && selected.isSelected
            && !selected.label.hasSuffix(", Try again") && selected.label.contains("Native player")
        captureEvidence(surface: "Observed existing \(label) after bounded native preparation")
        try closeSourceSheetIfPresent()
        guard isRequestedOwner, let ready else {
            throw XCTSkip("The requested existing source did not prove selected, ready advancing native playback. A Web route or automatic fallback cannot qualify AVKit controls.")
        }
        let owner = try strictNativeOwner(identifier: "native-playback-measurement")
        assertSharedNativeOwner(owner, expected: ready, stage: "Requested native source after picker dismissal")
        baseline = owner
        if ProcessInfo.processInfo.environment["FOTTY_VIDEO_FIRST_HOLD_SECONDS"] == "90" {
            try holdSelectedNativeSourceForNinetySeconds(expected: owner, label: label)
        }
        try enterNativeFullscreen(expected: owner)
        try tapActualNativeFullscreenControl(.pause, expected: owner)
        try assertNativeFullscreenPaused(expected: owner)
        captureEvidence(surface: "Video-first actual Apple fullscreen paused")
        try exitNativeFullscreen(expected: owner)
        assertViewingPause(usesNativeTransport: true)
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
            expected: owner, stage: "Apple Done retains paused inline owner")
        try enterNativeFullscreen(expected: owner)
        try assertNativeFullscreenPaused(expected: owner)
        try tapActualNativeFullscreenControl(.play, expected: owner)
        try requireNativeFullscreenProgress(expected: owner, stage: "Actual Apple Play after paused fullscreen re-entry")
        captureEvidence(surface: "Video-first actual Apple fullscreen resumed")
        try exitNativeFullscreen(expected: owner)
        let resumed = try XCTUnwrap(nativeLayerAndMediaProgressMeasurement(timeout: 15),
            "Apple Done must restore ready advancing inline playback without replacing the stream")
        assertSharedNativeOwner(resumed, expected: owner, stage: "Apple Done restores advancing inline owner")
        try openSources(requirePreviouslyObservedPicker: true)
        XCTAssertTrue(sourceRows.matching(identifier: identifier).firstMatch.isSelected,
                      "Fullscreen must not change the selected source")
        try closeSourceSheetIfPresent()
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
            expected: owner, stage: "Source controls after Apple fullscreen return")
        captureEvidence(surface: "Video-first inline playback after actual Apple controls")
        navigationTimings.append("Existing \(label) selected through normal Home picker; ready native video/progress. Two actual AVKit presentations: Pause/stable time, paused Done/inline, paused re-entry, Apple Play/advancing time, Done/advancing inline; same player/item/attempt and selected source. Not PiP, audible output, source-wide qualification or a sustained decoder soak.")
        try closePlayer()
        capturedFocusedEnd = true
    }

    /// Optional real-programme hold for a named existing source. No injected
    /// fixture/media or alternate-source progress can satisfy this gate. Ready
    /// layer samples and advancing time are not a continuous pixel-buffer count;
    /// contemporaneous screenshots must independently confirm the programme.
    private func holdSelectedNativeSourceForNinetySeconds(expected: [String: Any], label: String) throws {
        let first = try strictNativeOwner(identifier: "native-playback-measurement")
        let startTime = try XCTUnwrap(first["currentTimeSeconds"] as? Double)
        let startedAt = ProcessInfo.processInfo.systemUptime
        var nextReceipt: TimeInterval = 0
        captureEvidence(surface: "Selected \(label) live programme hold start")
        while ProcessInfo.processInfo.systemUptime - startedAt < 90 {
            let sample = try strictNativeOwner(identifier: "native-playback-measurement")
            for key in ["playerToken", "itemToken", "attemptToken"] {
                XCTAssertEqual(sample[key] as? String, expected[key] as? String,
                               "Selected \(label) was replaced during its live hold: \(key)")
            }
            XCTAssertEqual(sample["readyForDisplay"] as? Bool, true,
                           "Selected \(label) has no ready displayed video")
            XCTAssertGreaterThan(sample["renderedPixelWidth"] as? Double ?? 0, 0)
            XCTAssertGreaterThan(sample["renderedPixelHeight"] as? Double ?? 0, 0)
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            if elapsed >= nextReceipt {
                attachNativeMeasurementScalars(sample, name: "Selected \(label) live hold \(Int(elapsed))s")
                nextReceipt += 30
            }
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        let final = try strictNativeOwner(identifier: "native-playback-measurement")
        assertSharedNativeOwner(final, expected: expected, stage: "Selected \(label) complete live hold")
        let finalTime = try XCTUnwrap(final["currentTimeSeconds"] as? Double)
        XCTAssertTrue(startTime.isFinite && finalTime.isFinite && finalTime - startTime >= 80,
                      "Selected \(label) did not advance at least80s during the90s hold")
        captureEvidence(surface: "Selected \(label) live programme hold end")
        navigationTimings.append("Selected \(label):90s bounded ready-layer hold; same player/item/attempt, media advance=\(finalTime - startTime)s. Correct programme needs screenshot review; no continuous decoded-pixel, audible-output or league-wide uptime claim.")
    }

    private func openVideoFirstHomePlayback() throws {
        // Home Watch only. The existing generic helper can fall back to a
        // Search channel, which must not substitute for this production journey.
        // The hero container's ID also propagates to its options menu. Choose
        // the explicit playback button, not the first hittable descendant.
        var watches = app.buttons.matching(NSPredicate(format:
            "(identifier BEGINSWITH %@ OR identifier == %@) AND label BEGINSWITH[c] %@",
            "match-start-play-", "home-watch-now", "Watch"))
        if let match = ProcessInfo.processInfo.environment["FOTTY_VIDEO_FIRST_TEST_MATCH"] {
            guard !match.isEmpty, match.count <= 160,
                  !match.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                return XCTFail("The optional test match must name a bounded real Home button, not supply fixture data")
            }
            watches = watches.matching(NSPredicate(format: "label CONTAINS[c] %@", match))
        }
        _ = watches.firstMatch.waitForExistence(timeout: 15)
        guard let watch = watches.allElementsBoundByIndex.first(where: { $0.isHittable && $0.isEnabled }) else {
            captureEvidence(surface: "Video-first gate: no real Home Watch available")
            throw XCTSkip("No currently watchable real Home row was available; no seeded fixture or Search channel was substituted.")
        }
        tap(watch)
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.player.exists || self.app.descendants(matching: .any)["stream-resolution-panel"].exists
                || self.app.alerts["Stream Not Available"].exists
        }, "Real Home Watch produced no prompt feedback")
        guard player.waitForExistence(timeout: 40) else {
            captureEvidence(surface: "Video-first gate: real Home delivery unavailable")
            throw XCTSkip("The real Home lookup supplied no player in its bounded window; layout/native playback is unqualified.")
        }
        XCTAssertTrue(app.buttons["viewing-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["viewing-control-dock"].firstMatch.exists)
        XCTAssertTrue(app.buttons["viewing-sources"].isHittable)
        XCTAssertTrue(app.buttons["viewing-details"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["viewing-companion"].firstMatch.exists,
                       "Match companion must be on demand, not permanently beside the iPad video")

    }

    private func exerciseVideoFirstRotation(before: [String: Any]?, preservesPause: Bool,
                                             usesNativeTransport: Bool) throws {
        let original = XCUIDevice.shared.orientation
        let details = app.buttons["viewing-details"]
        let initial = try XCTUnwrap(positiveAppWindow(containing: details)).frame
        let restore = original.isPortrait || original.isLandscape
            ? original : (initial.width > initial.height ? .landscapeLeft : .portrait)
        defer { XCUIDevice.shared.orientation = restore }
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(waitUntil(timeout: 8) {
                guard let current = self.positiveAppWindow(containing: details) else { return false }
                let frame = current.frame
                return (orientation.isPortrait ? frame.height > frame.width : frame.width > frame.height) && details.isHittable
            }, "The real video-first window did not reflow to \(name)")
            XCTAssertTrue(app.buttons["viewing-details"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["viewing-companion"].firstMatch.exists)
            if let before {
                assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
                    expected: before, stage: "Video-first \(name) rotation")
            }
            if preservesPause { assertViewingPause(usesNativeTransport: usesNativeTransport) }
            let media = app.descendants(matching: .any)["native-playback-measurement"].firstMatch
            let dock = app.descendants(matching: .any)["viewing-control-dock"].firstMatch
            if media.exists, finitePositiveFrame(media.frame), dock.exists, finitePositiveFrame(dock.frame),
               let current = positiveAppWindow(containing: details) {
                let frame = media.frame
                XCTAssertEqual(frame.width / frame.height, 16.0 / 9.0, accuracy: 0.04,
                               "The complete native video slot must remain 16:9, not a clipped scrolling surface")
                XCTAssertTrue(current.frame.insetBy(dx: -2, dy: -2).contains(frame), "The whole video must fit its real app window")
                let overlap = frame.intersection(dock.frame)
                XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                              "The dock must not cover the retained media or steal its controls")
                navigationTimings.append("Video-first \(name) actual AX frames: media=\(frame), dock=\(dock.frame); 16:9/whole-window/non-overlap checked.")
            } else {
                navigationTimings.append("Video-first \(name): no reliable finite native hook/dock frames; screenshot captured, geometry remains visual-review evidence only.")
            }
            captureEvidence(surface: "Actual video-first iPad \(name)")
        }
        XCUIDevice.shared.orientation = restore
        XCTAssertTrue(waitUntil(timeout: 8) {
            guard let current = self.positiveAppWindow(containing: details) else { return false }
            return (restore.isPortrait ? current.frame.height > current.frame.width : current.frame.width > current.frame.height)
                && details.isHittable
        }, "The video-first player did not restore the original orientation")
        if let before {
            assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
                expected: before, stage: "Video-first original orientation restored")
        }
    }

    /// Real, reviewed CS only. Focus changes layout; this gate instead opens
    /// the actual AVPlayerViewController and uses its exposed Apple controls.
    func testPhysicalNativeFullscreenSystemControlsRetainRealCommunitySource() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This named acceptance gate is for Jet iPad only.")
        }
        executionTimeAllowance = 240
        let qualified = try qualifyReviewedCommunitySource(leavePlayerOpen: true, attemptTimeout: 90)
        let baseline = try strictNativeOwner(identifier: "native-playback-measurement")
        try verifyQualifiedCommunitySource(qualified)

        try enterNativeFullscreen(expected: baseline)
        try tapActualNativeFullscreenControl(.pause, expected: baseline)
        try assertNativeFullscreenPaused(expected: baseline)
        try exitNativeFullscreen(expected: baseline)
        assertViewingPause(usesNativeTransport: true)
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
                               expected: baseline, stage: "First fullscreen exit deliberately remains paused")

        // A second native presentation must not restart playback or resolve
        // the source again merely because a previously paused owner is shown.
        try enterNativeFullscreen(expected: baseline)
        try assertNativeFullscreenPaused(expected: baseline)
        try tapActualNativeFullscreenControl(.play, expected: baseline)
        try requireNativeFullscreenProgress(expected: baseline, stage: "Apple Play after paused re-entry")
        try tapActualNativeFullscreenControl(.pause, expected: baseline)
        try assertNativeFullscreenPaused(expected: baseline)
        try tapActualNativeFullscreenControl(.play, expected: baseline)
        try requireNativeFullscreenProgress(expected: baseline, stage: "Repeated Apple Pause/Play on the same native owner")
        try exitNativeFullscreen(expected: baseline)
        let restored = try XCTUnwrap(nativeLayerAndMediaProgressMeasurement(timeout: 8),
                                    "Returning from native fullscreen did not restore a ready advancing inline layer")
        assertSharedNativeOwner(restored, expected: baseline, stage: "Second native fullscreen return")
        try verifyQualifiedCommunitySource(qualified)
        navigationTimings.append("Actual native fullscreen: two presentations/returns, deliberate paused entry, real Apple Pause/Play, same player/item/attempt and advancing ready fullscreen/inline receipts. Not continuous decoded-frame or audible-playback proof.")
        try closePlayer()
        capturedFocusedEnd = true
    }

    /// This is a separate real-source run, not identity continuity between test
    /// methods. No reference HLS fixture or unrelated channel can qualify it.
    func testPhysicalNativeFullscreenPictureInPictureRetainsRealCommunitySource() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This named acceptance gate is for Jet iPad only.")
        }
        executionTimeAllowance = 240
        let qualified = try qualifyReviewedCommunitySource(leavePlayerOpen: true, attemptTimeout: 90)
        try exerciseActualNativeFullscreenPiPRoundTrip(qualifiedCS: qualified)
    }

    /// A reviewed public fixture ID selects an existing Home row; it supplies
    /// no fixture/status/source data and enables no provider. A truthful lookup
    /// end without native progress leaves playback/fullscreen/PiP unqualified.
    func testPhysical186ReviewedFixtureLookupAndNativeFullscreenPiP() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The reviewed-fixture/native playback gate is for Jet iPad only.")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:")
        guard let fixtureID = ProcessInfo.processInfo.environment["FOTTY_FIXTURE_GATE_ID"],
              !fixtureID.isEmpty, fixtureID.count <= 180,
              fixtureID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw XCTSkip("Supply one freshly reviewed public ID for an existing eligible official fixture.")
        }
        let optionsLabel = ProcessInfo.processInfo.environment["FOTTY_FIXTURE_GATE_OPTIONS_LABEL"]
        if let optionsLabel {
            guard optionsLabel.hasPrefix("More options for "), optionsLabel.count <= 240,
                  !optionsLabel.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw XCTSkip("The optional semantic fixture route must be one bounded, freshly reviewed exact native options label.")
            }
        }
        // Wide native overview containers can propagate their identifier to
        // leaf controls. Use an exact reviewed semantic fallback only when the
        // requested leaf ID is absent, and reject every ambiguous match.
        func nativeControl(id: String, exactLabel: String?) -> XCUIElement? {
            let identified = app.buttons.matching(identifier: id).allElementsBoundByAccessibilityElement
            let candidates = identified.isEmpty
                ? exactLabel.map { app.buttons.matching(NSPredicate(format: "label == %@", $0)).allElementsBoundByAccessibilityElement } ?? []
                : identified
            let visible = candidates.filter { $0.isHittable }
            return visible.count == 1 ? visible[0] : nil
        }
        let directOutageGate = ProcessInfo.processInfo.environment["FOTTY_FIXTURE_GATE_DIRECT_CHECK"] == "1"
        executionTimeAllowance = directOutageGate ? 420 : 240
        let deadline = Date().addingTimeInterval(directOutageGate ? 405 : 225)
        var baseline: [String: Any]?
        var expandedMore = false
        let selectedSports = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@", "home-sport-", "home-wide-overview"))
            .allElementsBoundByAccessibilityElement.filter { $0.isSelected && $0.isHittable }
        let originalSelection = selectedSports.count == 1 ? selectedSports[0] : nil
        let originalSport = originalSelection?.identifier.hasPrefix("home-sport-") == true ? originalSelection?.identifier : nil
        let originalSportLabel = originalSelection?.label
        defer {
            if app.state != .runningForeground { app.activate() }
            if let baseline {
                if app.otherElements["PIPUIView"].firstMatch.exists {
                    try? restoreActualSystemPictureInPicture(expected: baseline)
                }
                if app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch.exists {
                    try? exitNativeFullscreen(expected: baseline)
                }
            }
            let lookupCancel = app.buttons["stream-resolution-cancel"]
            if lookupCancel.exists && lookupCancel.isHittable { tap(lookupCancel) }
            let nativeLookup = app.descendants(matching: .any)["viewing-resolution"].firstMatch
            let cancel = app.buttons["Cancel"].firstMatch
            if nativeLookup.exists && cancel.isHittable { tap(cancel) }
            for title in ["Broadcast not ready", "Stream Not Available"] {
                let alert = app.alerts[title]
                if alert.exists && alert.buttons["OK"].isHittable { tap(alert.buttons["OK"]) }
            }
            try? closeSourceSheetIfPresent()
            if player.exists { try? closePlayer() }
            let closeDetails = app.navigationBars["Match details"].buttons["Close"].firstMatch
            if closeDetails.exists && closeDetails.isHittable { tap(closeDetails) }
            if expandedMore {
                let more = app.buttons["home-more-live"]
                if more.exists && more.value as? String == "Expanded" {
                    try? reveal(more)
                    if more.isHittable { tap(more) }
                }
            }
            if originalSport != nil || originalSportLabel != nil {
                var original = nativeControl(id: originalSport ?? "home-sport-original-selection", exactLabel: originalSportLabel)
                for _ in 0..<5 where original == nil {
                    guard visibleContentScroll.exists else { break }
                    visibleContentScroll.swipeDown()
                    original = nativeControl(id: originalSport ?? "home-sport-original-selection", exactLabel: originalSportLabel)
                }
                if let original, !original.isSelected { tap(original) }
            }
        }
        try selectTab("tab-home", surface: "Reviewed current official fixture lookup")
        var allSports = nativeControl(id: "home-sport-all-sports", exactLabel: "All sports")
        for _ in 0..<5 where allSports == nil {
            guard visibleContentScroll.exists else { break }
            visibleContentScroll.swipeDown()
            allSports = nativeControl(id: "home-sport-all-sports", exactLabel: "All sports")
        }
        guard let allSports else {
            throw XCTSkip("The normal Home All sports route is not currently reachable; no filter preference was rewritten.")
        }
        if !allSports.isSelected { tap(allSports) }
        let directLabel = optionsLabel.map { "Check streams for " + $0.dropFirst("More options for ".count) }
        let watchLabel = optionsLabel.map { "Watch " + $0.dropFirst("More options for ".count) }
        func directSourceControl() -> XCUIElement? {
            nativeControl(id: "match-start-check-streams-\(fixtureID)", exactLabel: directLabel)
                ?? nativeControl(id: "match-start-play-\(fixtureID)", exactLabel: watchLabel)
        }
        var direct = directOutageGate ? directSourceControl() : nil
        // Rows show one action; the fixture's details are in its long-press menu.
        var menu = nativeControl(id: "home-event-\(fixtureID)", exactLabel: nil)
        if directOutageGate {
            for _ in 0..<7 where direct == nil {
                let more = app.buttons["home-more-live"]
                if more.exists && more.isHittable && more.value as? String == "Collapsed" {
                    tap(more); expandedMore = true
                } else if visibleContentScroll.exists { visibleContentScroll.swipeUp() }
                else { break }
                direct = directSourceControl()
            }
        }
        if let direct {
            XCTAssertGreaterThanOrEqual(direct.frame.height, 44)
            XCTAssertTrue(direct.isEnabled)
            captureEvidence(surface: "187 exact fixture visible Home source action during catalog outage")
            tap(direct)
        } else {
        guard !directOutageGate else {
            captureEvidence(surface: "187 exact Home Check streams action not reachable")
            return XCTFail("The freshly reviewed eligible fixture must have direct Home Check streams or a freshly admitted Watch action; Details is not a substitute for this outage drill.")
        }
        for _ in 0..<7 where menu == nil {
            let more = app.buttons["home-more-live"]
            if more.exists && more.isHittable && more.value as? String == "Collapsed" {
                tap(more); expandedMore = true
            } else if visibleContentScroll.exists { visibleContentScroll.swipeUp() }
            else { break }
            menu = nativeControl(id: "home-event-\(fixtureID)", exactLabel: nil)
        }
        guard let menu else {
            captureEvidence(surface: "Reviewed official fixture no longer visible in the current Home lineup")
            throw XCTSkip("The reviewed fixture route is absent or ambiguous in this current Home scope; no fixture, interest or source setting was injected.")
        }
        navigationTimings.append("Existing fixture route retained the reviewed public ID and selected one unique native menu. Exact semantic fallback, when the leaf ID is absent, is an accessibility test route only; normal fixture/source admission remains authoritative.")
        menu.press(forDuration: 1.0)
        tap(app.buttons["Match details"].firstMatch)
        let check = app.buttons["match-details-check-streams"]
        guard check.waitForExistence(timeout: 6) else {
            captureEvidence(surface: "Reviewed fixture has no currently eligible Check streams action")
            throw XCTSkip("The current fixture or enabled-source policy no longer offers Check streams; discovery/playback is unqualified.")
        }
        try reveal(check)
        guard check.isEnabled else {
            throw XCTSkip("The existing fixture Check streams action is currently unavailable; no admission rule was overridden.")
        }
        tap(check)
        }
        let resolution = app.descendants(matching: .any)["viewing-resolution"].firstMatch
        let panel = app.descendants(matching: .any)["stream-resolution-panel"].firstMatch
        func truthfulEnd() -> Bool {
            app.alerts["Broadcast not ready"].exists || app.alerts["Stream Not Available"].exists
        }
        XCTAssertTrue(waitUntil(timeout: 5) { resolution.exists || panel.exists || self.player.exists || truthfulEnd() },
                      "Check streams supplied no immediate resolution, player or truthful end feedback")
        let resultBudget = min(45, max(0, deadline.timeIntervalSinceNow - 145))
        guard resultBudget > 0,
              waitUntil(timeout: resultBudget, { self.player.exists || truthfulEnd() }) else {
            captureEvidence(surface: "Reviewed fixture source lookup remains pending within bounded physical gate")
            throw XCTSkip("The acknowledged lookup has no player/truthful terminal result within this bounded gate; native playback and controls remain unqualified.")
        }
        guard player.exists else {
            captureEvidence(surface: "Reviewed fixture returned a truthful unavailable or changed-fixture result")
            throw XCTSkip("The real source check returned no player; unavailable/changed fixtures cannot qualify playback, fullscreen or PiP.")
        }
        var sourceProof: (identifier: String, family: String)?
        if directOutageGate {
            try revealPlayerChrome()
            try openSources()
            let rows = sourceRows.matching(NSPredicate(format: "label MATCHES %@", "^CS[1-6], .+"))
                .allElementsBoundByIndex
            guard let selected = rows.first(where: { $0.isSelected }) ?? rows.first else {
                throw XCTSkip("The normal picker contains no current admitted CS choice; the dated listing alone does not qualify a delivery.")
            }
            let proof = (identifier: selected.identifier, family: String(selected.label.split(separator: ",", maxSplits: 1)[0]))
            if !selected.isSelected || selected.label.hasSuffix(", Try again") {
                try reveal(selected); tap(selected)
            }
            sourceProof = proof
            captureEvidence(surface: "187 independent CS choice in the existing normal source picker")
            try closeSourceSheetIfPresent()
        }
        let nativeBudget = min(30, max(0, deadline.timeIntervalSinceNow - 130))
        guard nativeBudget > 0,
              let ready = nativeLayerAndMediaProgressMeasurement(timeout: nativeBudget,
                evidenceName: "Reviewed official fixture actual native setup") else {
            captureEvidence(surface: "Reviewed fixture did not prove ready advancing native playback")
            throw XCTSkip("No ready native layer and advancing media qualified; a Web route or player clock alone is not an AVKit pass.")
        }
        baseline = try strictNativeOwner(identifier: "native-playback-measurement")
        let owner = try XCTUnwrap(baseline)
        assertSharedNativeOwner(owner, expected: ready, stage: "Reviewed fixture qualified native owner")
        let qualified = sourceProof.map { QualifiedCommunitySource(identifier: $0.identifier, family: $0.family, nativeMeasurement: owner) }
        let focusedPiPRetry = directOutageGate && ProcessInfo.processInfo.environment["FOTTY_FIXTURE_GATE_FOCUSED_PIP"] == "1"
        if directOutageGate && !focusedPiPRetry {
            if let qualified { try verifyQualifiedCommunitySource(qualified) }
            try holdSelectedNativeSourceForNinetySeconds(expected: owner, label: sourceProof?.family ?? "current independent source")
            if let qualified { try verifyQualifiedCommunitySource(qualified) }
        }
        guard deadline.timeIntervalSinceNow > 130 else {
            throw XCTSkip("Native setup qualified, but the bounded gate has insufficient time for the complete fullscreen/PiP check.")
        }
        if !focusedPiPRetry {
            try enterNativeFullscreen(expected: owner)
            try tapActualNativeFullscreenControl(.pause, expected: owner)
            try assertNativeFullscreenPaused(expected: owner)
            try tapActualNativeFullscreenControl(.play, expected: owner)
            try requireNativeFullscreenProgress(expected: owner, stage: "Reviewed fixture actual AVKit Resume")
            try exitNativeFullscreen(expected: owner)
        } else {
            navigationTimings.append("Focused PiP rerun: previous187 CS2 sustained hold/fullscreen controls remain separately scoped; this run does not repeat or requalify that hold.")
        }
        guard deadline.timeIntervalSinceNow > 100 else {
            throw XCTSkip("Fullscreen Pause/Resume/Done ran; insufficient bounded time remains for the full60s PiP round trip, which stays unqualified.")
        }
        try exerciseActualNativeFullscreenPiPRoundTrip(qualifiedCS: qualified)
        navigationTimings.append("Reviewed existing official fixture: normal Home All sports → exact match options → Match details → eligible Check streams → real native progress → actual fullscreen Pause/Resume/Done → one system PiP round trip. No source enablement, fixture/status injection, Report or quality extras.")
    }

    /// The fullscreen owner is source-independent. An available real channel
    /// may qualify this separate native presentation gate, never the CS gate
    /// above or a claim that a particular match is airing on that channel.
    func testPhysicalNativeFullscreenPictureInPictureRetainsRealNativeSource() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This named acceptance gate is for Jet iPad only.")
        }
        executionTimeAllowance = 240
        try openRealPlayback()
        let deadline = Date().addingTimeInterval(90)
        var ready = waitForNativeLayerAndMediaProgress(timeout: 25)
        var attempted: Set<String> = []
        for _ in 0..<2 where !ready && Date() < deadline {
            try openSources()
            guard let alternative = sourceRows.allElementsBoundByIndex.first(where: {
                !$0.isSelected && !attempted.contains($0.identifier)
            }) else {
                try closeSourceSheetIfPresent()
                break
            }
            attempted.insert(alternative.identifier)
            tap(alternative)
            ready = waitForNativeLayerAndMediaProgress(timeout: min(30, deadline.timeIntervalSinceNow))
        }
        guard ready else {
            captureEvidence(surface: "Available real broadcast did not qualify native fullscreen PiP setup")
            try closePlayer()
            throw XCTSkip("No ready advancing native source qualified within the bounded real-broadcast setup; WebKit or metadata is not native proof.")
        }
        try exerciseActualNativeFullscreenPiPRoundTrip(qualifiedCS: nil)
    }

    private func exerciseActualNativeFullscreenPiPRoundTrip(qualifiedCS: QualifiedCommunitySource?) throws {
        let baseline = try strictNativeOwner(identifier: "native-playback-measurement")
        if let qualifiedCS { try verifyQualifiedCommunitySource(qualifiedCS) }
        try enterNativeFullscreen(expected: baseline)
        try requireNativeFullscreenProgress(expected: baseline, stage: "Fresh real native owner immediately before system PiP")
        // Reacquire both control and real owner now; never reuse a coordinate
        // from an earlier presentation or a source before failover.
        let pip = try actualNativeFullscreenControl(.pictureInPicture, expected: baseline)
        let before = try strictNativeOwner(identifier: "native-fullscreen-measurement")
        assertSharedNativeOwner(before, expected: baseline, stage: "System PiP admission")
        tap(pip)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let started = waitUntil(timeout: 10) { self.actualSystemPiPSurface() != nil }
        if !started {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Actual native PiP start did not expose a system window"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertTrue(started, "AVKit PiP did not visibly start before Home; a button tap or willStart flag is not start evidence")
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 6), "Native fullscreen PiP did not expose the real Home surface")
        let homeIcon = try XCTUnwrap(springboard.icons.allElementsBoundByAccessibilityElement.prefix(12).first { $0.isHittable },
                                    "No real hittable Home icon confirms the PiP Home transition")
        let end = Date().addingTimeInterval(60)
        var nextVisibilityCheck = Date()
        while Date() < end {
            XCTAssertTrue([XCUIApplication.State.runningBackground, .runningForeground].contains(app.state),
                          "Fotty stopped or suspended during the bounded native fullscreen PiP interval")
            XCTAssertEqual(springboard.state, .runningForeground)
            if Date() >= nextVisibilityCheck {
                XCTAssertTrue(homeIcon.exists && homeIcon.isHittable)
                XCTAssertNotNil(actualSystemPiPSurface(), "The actual system PiP window disappeared during the Home hold")
                nextVisibilityCheck = Date().addingTimeInterval(5)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Actual native fullscreen PiP after 60 seconds on Home"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Use the actual exposed system Restore control, not the inline
        // AVPlayerLayer's separate command or a prior app.activate() transition.
        try restoreActualSystemPictureInPicture(expected: baseline, fromSystemHome: true)
        let after = try strictNativeOwner(identifier: "native-fullscreen-measurement")
        assertSharedNativeOwner(after, expected: baseline, stage: "Native fullscreen PiP restoration")
        let earlier = try XCTUnwrap(before["currentTimeSeconds"] as? Double)
        let later = try XCTUnwrap(after["currentTimeSeconds"] as? Double)
        XCTAssertTrue(earlier.isFinite && later.isFinite && later > earlier + 30,
                      "The same native owner did not advance across the full 60-second Home round trip")
        try requireNativeFullscreenProgress(expected: baseline, stage: "Restored actual AVKit fullscreen advances")
        try exitNativeFullscreen(expected: baseline)
        let restored = try XCTUnwrap(nativeLayerAndMediaProgressMeasurement(timeout: 8),
                                    "System PiP restoration/Close did not return a ready advancing inline layer")
        assertSharedNativeOwner(restored, expected: baseline, stage: "System PiP stopped and original inline owner restored")
        if let qualifiedCS { try verifyQualifiedCommunitySource(qualifiedCS) }
        navigationTimings.append("Actual AVKit fullscreen→system PiP→60s visible Home→system Restore→native Close. Same player/item/attempt; media-time advance=\(later - earlier)s. Sampled Home/process state, not continuous background frame/audio proof; a return-to-live seek is not ruled out. Muted XCTest mode cannot qualify audible playback.")
        try closePlayer()
        capturedFocusedEnd = true
    }

    private enum NativeFullscreenAction {
        case pause, play, close, pictureInPicture
        var labelPattern: String {
            switch self {
            case .pause: return #"^(?:Pause|Pause playback|Pause video)$"#
            case .play: return #"^(?:Play|Play playback|Play video|Resume)$"#
            case .close: return #"^(?:Close|Done|Exit full screen|Exit fullscreen|Close full screen)$"#
            case .pictureInPicture: return #"^(?:Picture in Picture|Start Picture in Picture|Enter Picture in Picture|minimize video)$"#
            }
        }
        // Observed identifiers from the real Jet AVKit hierarchy. The shared
        // transport toggle has no label on this OS; direction requires rate.
        var observedSystemIdentifier: String {
            switch self {
            case .pause, .play: return "Play/Pause"
            case .close: return "Close Button"
            case .pictureInPicture: return "PIP Button"
            }
        }
    }

    private func strictNativeOwner(identifier: String) throws -> [String: Any] {
        let receipt = try XCTUnwrap(readNativeMeasurement(identifier: identifier),
                                   "The real native \(identifier) receipt is unavailable")
        for key in ["playerToken", "itemToken", "attemptToken"] {
            let value = try XCTUnwrap(receipt[key] as? String, "Missing real native \(key)")
            XCTAssertNotNil(UUID(uuidString: value), "The real native \(key) is not an opaque UUID")
        }
        return receipt
    }
    private func assertSharedNativeOwner(_ current: [String: Any], expected: [String: Any], stage: String) {
        for key in ["playerToken", "itemToken", "attemptToken"] {
            XCTAssertEqual(current[key] as? String, expected[key] as? String, "\(stage): \(key) changed")
        }
        attachNativeMeasurementScalars(current, name: stage)
    }
    private func enterNativeFullscreen(expected: [String: Any]) throws {
        let button = app.buttons["viewing-native-fullscreen"]
        try reveal(button)
        XCTAssertTrue(waitUntil(timeout: 8) { button.isHittable && button.isEnabled },
                      "The current ready native owner must enable the real Fullscreen action")
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
                               expected: expected, stage: "Native fullscreen entry owner")
        tap(button)
        let presented = app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch.waitForExistence(timeout: 8)
        if !presented {
            captureEvidence(surface: "Actual native Fullscreen action did not present")
            if let inline = readNativeMeasurement(identifier: "native-playback-measurement") {
                assertSharedNativeOwner(inline, expected: expected, stage: "Inline owner after missing native presentation")
            }
        }
        XCTAssertTrue(presented,
                      "The real AVKit fullscreen measurement did not appear")
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-fullscreen-measurement"),
                               expected: expected, stage: "Actual presented AVKit owner")
    }
    private func positiveAppWindow(containing control: XCUIElement) -> XCUIElement? {
        guard control.exists else { return nil }
        let target = control.frame
        guard finitePositiveFrame(target) else { return nil }
        return app.windows.allElementsBoundByAccessibilityElement.map { ($0, $0.frame) }
            .filter { finitePositiveFrame($0.1) && $0.1.contains(target) && $0.0.isHittable }
            .max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
    }
    private func finitePositiveFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
    }
    private func actualNativeFullscreenControl(_ action: NativeFullscreenAction,
                                               expected: [String: Any]) throws -> XCUIElement {
        let marker = app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch
        let admission = try strictNativeOwner(identifier: "native-fullscreen-measurement")
        assertSharedNativeOwner(admission,
                               expected: expected, stage: "Native system control admission")
        if action == .pause {
            XCTAssertGreaterThan(try XCTUnwrap(admission["rate"] as? Double), 0,
                                 "A native transport toggle cannot qualify Pause unless currently playing")
        } else if action == .play {
            XCTAssertEqual(try XCTUnwrap(admission["rate"] as? Double), 0,
                           "A native transport toggle cannot qualify Play unless currently paused")
        }
        let window = try XCTUnwrap(positiveAppWindow(containing: marker),
                                   "No positive current window contains the real AVKit fullscreen measurement")
        func currentControl() -> XCUIElement? {
            app.buttons.matching(NSPredicate(format: "identifier == %@ OR label MATCHES[c] %@",
                                            action.observedSystemIdentifier, action.labelPattern))
                .allElementsBoundByAccessibilityElement.prefix(6).first {
                    $0.isHittable && !$0.identifier.hasPrefix("viewing-")
                        && !["close-live-player", "web-play-pause", "native-play-pause", "pause.fill", "play.fill"].contains($0.identifier)
                }
        }
        if let control = currentControl() { return control }
        // Only a verified native AVKit presentation can reach this ordinary
        // video-area tap. It reveals system chrome, not provider/Web transport.
        // AVKit can expose equal-sized auxiliary windows. Target its actual
        // Video element, not an arbitrary tie in the window query.
        let video = app.otherElements.matching(NSPredicate(format: "label == %@", "Video"))
            .allElementsBoundByAccessibilityElement.first { finitePositiveFrame($0.frame) && window.frame.contains($0.frame) }
        let videoFrame = try XCTUnwrap(video?.frame, "No actual AVKit Video geometry can reveal its system controls")
        let windowFrame = window.frame
        window.coordinate(withNormalizedOffset: CGVector(
            dx: (videoFrame.midX - windowFrame.minX) / windowFrame.width,
            dy: (videoFrame.minY + videoFrame.height * 0.3 - windowFrame.minY) / windowFrame.height)).tap()
        // Query first. A full diagnostic traversal can outlast auto-hide.
        if let control = currentControl() { return control }
        var found: XCUIElement?
        let exposed = waitUntil(timeout: 5) { found = currentControl(); return found != nil }
        if !exposed {
            let allButtons = app.buttons.allElementsBoundByAccessibilityElement.prefix(48).map {
                "label=\(String($0.label.prefix(120))); id=\(String($0.identifier.prefix(120))); type=\($0.elementType.rawValue); frame=\($0.frame); hittable=\($0.isHittable)"
            }
            let diagnostic = XCTAttachment(string: allButtons.joined(separator: "\n"))
            diagnostic.name = "Actual AVKit buttons before assertion"
            diagnostic.lifetime = .keepAlways; add(diagnostic)
            let windows = XCTAttachment(string: app.windows.allElementsBoundByAccessibilityElement
                .map { "id=\($0.identifier); frame=\($0.frame); hittable=\($0.isHittable)" }.joined(separator: "\n"))
            windows.name = "Actual native fullscreen windows before assertion"
            windows.lifetime = .keepAlways; add(windows)
            if let receipt = readNativeMeasurement(identifier: "native-fullscreen-measurement") {
                assertSharedNativeOwner(receipt, expected: expected, stage: "Native transport after chrome reveal")
            }
            let tree = XCTAttachment(string: String(app.debugDescription.prefix(60_000)))
            tree.name = "Actual fullscreen native hierarchy before missing-control assertion"
            tree.lifetime = .keepAlways; add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Actual fullscreen before missing-control assertion"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertTrue(exposed,
                      "The actual AVKit system \(action) control was not exposed; no fabricated test button was substituted")
        return try XCTUnwrap(found)
    }
    private func tapActualNativeFullscreenControl(_ action: NativeFullscreenAction,
                                                  expected: [String: Any]) throws {
        // The selector already validates the current native owner before
        // revealing/finding AVKit chrome. Another full AX traversal here can
        // outlast its auto-hide interval and invalidate the returned button.
        // Tap the real exposed system control immediately; callers still
        // verify exact ownership and the resulting transport after the action.
        let control = try actualNativeFullscreenControl(action, expected: expected)
        control.tap()
    }
    private func assertNativeFullscreenPaused(expected: [String: Any]) throws {
        var paused: [String: Any]?
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let receipt = self.readNativeMeasurement(identifier: "native-fullscreen-measurement"),
                  receipt["rate"] as? Double == 0, receipt["timeControlStatus"] as? Int == 0 else { return false }
            paused = receipt; return true
        }, "Apple Pause did not pause the real AVPlayer")
        let first = try XCTUnwrap(paused)
        assertSharedNativeOwner(first, expected: expected, stage: "Native system Pause actual transport")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let second = try strictNativeOwner(identifier: "native-fullscreen-measurement")
        assertSharedNativeOwner(second, expected: expected, stage: "Native paused stability sample")
        XCTAssertEqual(second["rate"] as? Double, 0)
        XCTAssertEqual(second["timeControlStatus"] as? Int, 0)
        let earlier = try XCTUnwrap(first["currentTimeSeconds"] as? Double)
        let later = try XCTUnwrap(second["currentTimeSeconds"] as? Double)
        XCTAssertTrue(earlier.isFinite && later.isFinite && abs(later - earlier) <= 0.25,
                      "The system-paused same native item continued advancing")
    }
    private func requireNativeFullscreenProgress(expected: [String: Any], stage: String) throws {
        var first: [String: Any]?
        var progressed: [String: Any]?
        // Real native owners retain the existing 12-second forward-buffer
        // target. Do not classify its bounded refill as rejected system Play.
        let advancing = waitUntil(timeout: 30) {
            guard let current = self.readNativeMeasurement(identifier: "native-fullscreen-measurement") else { return false }
            for key in ["playerToken", "itemToken", "attemptToken"] {
                guard current[key] as? String == expected[key] as? String else {
                    XCTFail("\(stage): the pinned real native \(key) changed")
                    return false
                }
            }
            guard current["readyForDisplay"] as? Bool == true,
                  (current["rate"] as? Double ?? 0) > 0,
                  current["timeControlStatus"] as? Int == 2,
                  let time = current["currentTimeSeconds"] as? Double, time.isFinite,
                  let uptime = current["uptimeSeconds"] as? Double, uptime.isFinite else { return false }
            if let first, let oldTime = first["currentTimeSeconds"] as? Double,
               let oldUptime = first["uptimeSeconds"] as? Double, uptime > oldUptime + 1 && time > oldTime + 0.2 {
                progressed = current; return true
            }
            if first == nil { first = current }
            return false
        }
        if !advancing {
            if let current = readNativeMeasurement(identifier: "native-fullscreen-measurement") {
                assertSharedNativeOwner(current, expected: expected, stage: "\(stage) current transport before failed-progress assertion")
            }
            let buttons = XCTAttachment(string: app.buttons.allElementsBoundByAccessibilityElement.prefix(24)
                .map { "id=\($0.identifier); label=\($0.label); hittable=\($0.isHittable); frame=\($0.frame)" }.joined(separator: "\n"))
            buttons.name = "\(stage) actual native controls before progress assertion"
            buttons.lifetime = .keepAlways; add(buttons)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(stage) actual native surface before progress assertion"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertTrue(advancing, "\(stage): the actual ready AVKit fullscreen player did not advance")
        assertSharedNativeOwner(try XCTUnwrap(progressed), expected: expected, stage: stage)
    }
    private func exitNativeFullscreen(expected: [String: Any]) throws {
        try tapActualNativeFullscreenControl(.close, expected: expected)
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.buttons["viewing-sources"].isHittable },
                      "Apple Close did not reveal the retained viewing layout")
        assertSharedNativeOwner(try strictNativeOwner(identifier: "native-playback-measurement"),
                               expected: expected, stage: "Native Close retains inline owner")
        captureEvidence(surface: "Retained layout after actual native fullscreen Close")
    }
    private func actualSystemPiPSurface() -> XCUIElement? {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        return [app, system].flatMap {
            $0.otherElements.matching(identifier: "PIPUIView").allElementsBoundByAccessibilityElement.prefix(4)
        }.first { $0.exists && $0.label == "Video" && finitePositiveFrame($0.frame) }
    }
    private func restoreActualSystemPictureInPicture(expected: [String: Any], fromSystemHome: Bool = false) throws {
        var observed: XCUIElement?
        XCTAssertTrue(waitUntil(timeout: 5) { observed = self.actualSystemPiPSurface(); return observed != nil },
                      "No actual system PiP surface was exposed after the Home round trip")
        let pip = try XCTUnwrap(observed)
        if !fromSystemHome {
            assertSharedNativeOwner(try strictNativeOwner(identifier: "native-fullscreen-measurement"),
                                   expected: expected, stage: "Actual system PiP restoration admission")
        }
        let pattern = #"^(?:Restore Full Screen|Restore fullscreen|Return to app|Restore)$"#
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func restore() -> XCUIElement? {
            let surface = pip.frame
            return [app, system].flatMap {
                $0.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", pattern))
                    .allElementsBoundByAccessibilityElement.prefix(4)
            }.first { $0.isHittable && finitePositiveFrame($0.frame) && surface.intersects($0.frame) }
        }
        var control = restore()
        if control == nil {
            // PiP is an OS-owned floating window. Synthesize the ordinary
            // surface tap through the public system host, not Fotty's backdrop.
            let surface = pip.frame, screen = system.frame
            XCTAssertTrue(finitePositiveFrame(screen) && screen.contains(surface))
            system.coordinate(withNormalizedOffset: CGVector(
                dx: (surface.midX - screen.minX) / screen.width,
                dy: (surface.minY + surface.height * 0.3 - screen.minY) / screen.height)).tap()
            // Act on a freshly exposed real control before diagnostic queries
            // consume the OS chrome's auto-hide interval.
            if let revealed = restore() {
                if !fromSystemHome {
                    assertSharedNativeOwner(try strictNativeOwner(identifier: "native-fullscreen-measurement"),
                                           expected: expected, stage: "Immediately before system-host PiP Restore")
                }
                tap(revealed)
                XCTAssertTrue(waitUntil(timeout: 8) {
                    !pip.exists && self.app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch.exists
                }, "System-host Restore did not close PiP and reveal actual native fullscreen")
                return
            }
            let systemButtons = XCTAttachment(string: system.buttons.allElementsBoundByAccessibilityElement
                .filter { finitePositiveFrame($0.frame) && surface.intersects($0.frame) }.prefix(24)
                .map { "id=\($0.identifier); label=\($0.label); frame=\($0.frame); hittable=\($0.isHittable)" }.joined(separator: "\n"))
            systemButtons.name = "Actual system-host PiP buttons immediately after reveal"
            systemButtons.lifetime = .keepAlways; add(systemButtons)
            let tree = XCTAttachment(string: String(app.debugDescription.prefix(60_000)))
            tree.name = "Actual system PiP hierarchy immediately after reveal"
            tree.lifetime = .keepAlways; add(tree)
            let restoredControl = waitUntil(timeout: 5) { control = restore(); return control != nil }
            if !restoredControl {
                let buttons = XCTAttachment(string: app.buttons.allElementsBoundByAccessibilityElement.prefix(24)
                    .map { "id=\($0.identifier); label=\($0.label); frame=\($0.frame); hittable=\($0.isHittable)" }.joined(separator: "\n"))
                buttons.name = "Actual PiP and foreground buttons before Restore assertion"
                buttons.lifetime = .keepAlways; add(buttons)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Actual PiP controls before Restore assertion"
                screenshot.lifetime = .keepAlways; add(screenshot)
            }
            XCTAssertTrue(restoredControl,
                          "The actual system PiP Restore control was not exposed; no app-layer PiP command was substituted")
        }
        let labels = pip.buttons.allElementsBoundByAccessibilityElement.prefix(12).map { String($0.label.prefix(120)) }
        let receipt = XCTAttachment(string: "Actual system PiP button labels=\(labels); positive surface frame=\(pip.frame). Fresh owner and control rechecked; no private API.")
        receipt.name = "Actual native fullscreen PiP Restore controls"
        receipt.lifetime = .keepAlways; add(receipt)
        if !fromSystemHome {
            assertSharedNativeOwner(try strictNativeOwner(identifier: "native-fullscreen-measurement"),
                                   expected: expected, stage: "Immediately before system PiP Restore")
        }
        tap(try XCTUnwrap(control))
        XCTAssertTrue(waitUntil(timeout: 8) {
            !pip.exists && self.app.descendants(matching: .any)["native-fullscreen-measurement"].firstMatch.exists
        }, "System PiP Restore did not close PiP and return the actual AVKit fullscreen owner")
    }

    func testPhysicalProductionLookupCancellationDoesNotOpenALatePlayer() throws {
        let watch = try realWatchControl()
        let started = Date()
        tap(watch)
        let cancel = app.buttons["stream-resolution-cancel"]
        guard cancel.waitForExistence(timeout: 2), cancel.isHittable else {
            if player.exists { try closePlayer() }
            throw XCTSkip("This production lookup completed before an in-flight cancellation could be exercised.")
        }
        navigationTimings.append("Watch feedback/cancel available: \(Int(Date().timeIntervalSince(started) * 1_000)) ms")
        tap(cancel)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !self.app.descendants(matching: .any)["stream-resolution-panel"].exists
                && self.tabControl("tab-home").isHittable
        })
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            XCTAssertFalse(player.exists, "A cancelled lookup presented a late player")
            XCTAssertEqual(app.state, .runningForeground)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        endSurface = "Home after cancellation; bounded 20-second late-result window"
    }

    /// Requires a ready native layer and same-item media-time progress across a bounded
    /// background interval. Muted XCTest mode cannot qualify audible playback.
    func testPhysicalNativePiPControlsWhenARealNativeSourceIsAvailable() throws {
        let environment = ProcessInfo.processInfo.environment
        let reviewedCSKeys = ["FOTTY_CS_TEST_QUERY", "FOTTY_CS_TEST_HOME", "FOTTY_CS_TEST_AWAY"]
        var nativeReady: Bool
        var qualifiedCS: QualifiedCommunitySource?
        if reviewedCSKeys.contains(where: { environment[$0] != nil }) {
            // Partial/invalid configuration is rejected by the same CS helper;
            // it must not silently fall back to an unrelated real broadcast.
            qualifiedCS = try qualifyReviewedCommunitySource(leavePlayerOpen: true, attemptTimeout: 90)
            nativeReady = waitForNativeLayerAndMediaProgress(timeout: 8)
        } else {
            try openRealPlayback()
            let deadline = Date().addingTimeInterval(100)
            nativeReady = waitForNativeLayerAndMediaProgress(timeout: 25)
            var attempted: Set<String> = []
            for _ in 0..<2 where !nativeReady && Date() < deadline {
                try openSources()
                guard let alternative = sourceRows.allElementsBoundByIndex.first(where: {
                    !$0.isSelected && !attempted.contains($0.identifier)
                }) else {
                    try closeSourceSheetIfPresent()
                    break
                }
                attempted.insert(alternative.identifier)
                tap(alternative)
                nativeReady = waitForNativeLayerAndMediaProgress(timeout: min(35, deadline.timeIntervalSinceNow))
            }
        }
        if let qualifiedCS { try verifyQualifiedCommunitySource(qualifiedCS) }
        try revealPlayerChrome()
        let start = app.buttons["Start Picture in Picture"]
        guard nativeReady, start.waitForExistence(timeout: 5), start.isHittable else {
            try closePlayer()
            throw XCTSkip("The bounded real-source setup did not retain a ready native layer with media-time progress and an available PiP control; WebKit is not native qualification.")
        }
        tap(start)
        let stop = app.buttons["Stop Picture in Picture"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8), "The native PiP request did not activate")
        let before = try readNativeMeasurement()
        if let qualifiedCS {
            assertNativeIdentity(before, matches: qualifiedCS.nativeMeasurement,
                                 message: "PiP started on a different native source than the qualified CS source")
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let runningPiPStates: [XCUIApplication.State] = [.runningBackground, .runningForeground]
        let beforeHomeStates = "Fotty=\(app.state.rawValue), SpringBoard=\(springboard.state.rawValue)"
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        // A real build138 screenshot showed Home and PiP onscreen while XCTest
        // still classified Fotty as foreground. Process classification alone
        // therefore is not this gate's UI-background receipt. Require the real
        // Home application plus a visible/hittable icon, not just a Home press.
        let reachedHome = waitUntil(timeout: 5) {
            springboard.state == .runningForeground && runningPiPStates.contains(self.app.state)
        }
        let homeIcon = springboard.icons.allElementsBoundByIndex.prefix(12).first {
            $0.exists && $0.isHittable
        }
        let homeReceipt = XCTAttachment(string: "Before Home: \(beforeHomeStates). After Home: Fotty=\(app.state.rawValue), SpringBoard=\(springboard.state.rawValue), visible/hittable Home icon=\(homeIcon != nil). PiP can remain classified foreground; this receipt requires visible SpringBoard and a running Fotty process. It does not assert decoded PiP frames or audible playback.")
        homeReceipt.name = "Native PiP Home transition and process classifications"
        homeReceipt.lifetime = .keepAlways
        add(homeReceipt)
        let homeScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        homeScreenshot.name = "Native PiP visible Home transition"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)
        XCTAssertTrue(reachedHome && homeIcon != nil,
                      "PiP did not reach a visible SpringBoard Home surface with Fotty still running")
        let visibleHomeIcon = try XCTUnwrap(homeIcon)
        let backgroundEnd = Date().addingTimeInterval(60)
        var nextHomeVisibilityCheck = Date().addingTimeInterval(5)
        while Date() < backgroundEnd {
            XCTAssertTrue(runningPiPStates.contains(app.state), "Fotty stopped or suspended during native PiP")
            XCTAssertEqual(springboard.state, .runningForeground,
                           "SpringBoard left the foreground during native PiP; a full-app foreground return is not background qualification")
            if Date() >= nextHomeVisibilityCheck {
                XCTAssertTrue(visibleHomeIcon.exists && visibleHomeIcon.isHittable,
                              "The retained Home surface became hidden during native PiP")
                nextHomeVisibilityCheck = Date().addingTimeInterval(5)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(runningPiPStates.contains(app.state))
        XCTAssertEqual(springboard.state, .runningForeground)
        XCTAssertTrue(visibleHomeIcon.exists && visibleHomeIcon.isHittable)
        app.activate()
        try revealPlayerChrome()
        XCTAssertTrue(stop.waitForExistence(timeout: 8), "Native PiP ownership did not survive backgrounding")
        let after = try readNativeMeasurement()
        XCTAssertEqual(before["itemToken"] as? String, after["itemToken"] as? String)
        XCTAssertEqual(before["attemptToken"] as? String, after["attemptToken"] as? String)
        if let qualifiedCS {
            assertNativeIdentity(after, matches: qualifiedCS.nativeMeasurement,
                                 message: "The qualified CS native identity did not survive the PiP round trip")
        }
        let earlier = try XCTUnwrap(before["currentTimeSeconds"] as? Double)
        let later = try XCTUnwrap(after["currentTimeSeconds"] as? Double)
        attachNativeMeasurementScalars(after, name: "Native PiP before returning inline ownership")
        XCTAssertTrue(earlier.isFinite && later.isFinite && later > earlier + 30,
                      "The same native item did not advance across the background/foreground round trip")
        // The measurement hook belongs to the inline AVPlayerLayer, not the
        // system PiP window. Return ownership before requiring inline pixels;
        // retain the exact-item/attempt and full background progression gate.
        try revealPlayerChrome()
        try uncoverStopPiPControlIfNeeded(stop)
        tap(stop)
        XCTAssertTrue(start.waitForExistence(timeout: 8), "The native PiP stop did not return ownership")
        attachNativeMeasurementScalars(try readNativeMeasurement(), name: "Native PiP after returning inline ownership")
        let restored = try XCTUnwrap(nativeLayerAndMediaProgressMeasurement(timeout: 8),
                                    "Native inline layer/media time did not progress after stopping PiP")
        assertNativeIdentity(restored, matches: before,
                             message: "Stopping PiP replaced the native item or attempt")
        if let qualifiedCS {
            assertNativeIdentity(restored, matches: qualifiedCS.nativeMeasurement,
                                 message: "Stopping PiP replaced the qualified CS native identity")
        }
        let evidence = XCTAttachment(string: "Same native item/attempt across a full 60-second visible-SpringBoard/Fotty-return round trip; media-time advance \(later - earlier) seconds. Fotty remained running and SpringBoard foreground on each process-state sample; the retained Home icon was checked every five seconds and at the end, not continuously. Muted test mode; not audible-playback proof, continuously sampled background playback or decoded-frame sampling. A live-window seek on foreground return is not ruled out.")
        evidence.name = "Native PiP ownership and media-time round trip"
        evidence.lifetime = .keepAlways
        add(evidence)
        try closePlayer()
        endSurface = "Home after real native PiP control round trip"
    }

    private func uncoverStopPiPControlIfNeeded(_ stop: XCUIElement) throws {
        if stop.isHittable { return }
        // Real Jet iPad evidence exposes the system PiP video in Fotty's AX
        // tree. Its default top-right position covers the app's Stop button.
        // Perform the normal user drag, not a forced tap through that window.
        // The physical CS2 receipt shows this remote Video surface onscreen
        // while XCTest reports it non-hittable. Require its exact identity and
        // valid frame before an ordinary drag; require actual movement and the
        // uncovered Stop button's hittability afterwards.
        let pip = app.otherElements.matching(identifier: "PIPUIView").firstMatch
        XCTAssertTrue(waitUntil(timeout: 3) {
            let frame = pip.frame
            return pip.exists && pip.label == "Video" && !frame.isNull && !frame.isInfinite
                && frame.width > 0 && frame.height > 0
                && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
        },
                      "The covered Stop control has no movable system PiP surface")
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first {
            let frame = $0.frame
            return !frame.isNull && !frame.isInfinite
                && frame.width > pip.frame.width && frame.height > pip.frame.height
                && frame.contains(pip.frame) && frame.contains(stop.frame)
        }, "No current full app window contains the system PiP surface and Stop control")
        let original = pip.frame
        pip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.2, dy: 0.75)))
        try revealPlayerChrome()
        XCTAssertTrue(waitUntil(timeout: 5) {
            pip.exists && pip.frame != original && !pip.frame.intersects(stop.frame) && stop.isHittable
        }, "The system PiP window did not uncover the ordinary Stop control")
        let evidence = XCTAttachment(string: "System PiP user drag: original frame \(original), final frame \(pip.frame); Stop frame \(stop.frame). Final non-overlap and ordinary hittability required; no forced tap.")
        evidence.name = "Native PiP system-window reposition before ordinary Stop"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func attachNativeMeasurementScalars(_ measurement: [String: Any], name: String) {
        var scalars: [String: Any] = [:]
        for key in ["readyForDisplay", "currentTimeSeconds", "renderedPixelWidth", "renderedPixelHeight",
                    "presentationWidth", "presentationHeight", "itemStatus", "timeControlStatus", "rate",
                    "uptimeSeconds"] {
            if let value = measurement[key] as? NSNumber, value.doubleValue.isFinite {
                scalars[key] = value
            }
        }
        for key in ["playerToken", "itemToken", "attemptToken"] {
            if let value = measurement[key] as? String, UUID(uuidString: value) != nil {
                scalars[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: scalars, options: [.sortedKeys]),
              data.count <= 1_024, let text = String(data: data, encoding: .utf8) else { return }
        let evidence = XCTAttachment(string: text)
        evidence.name = name
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func readNativeMeasurement() throws -> [String: Any] {
        let element = app.descendants(matching: .any)["native-playback-measurement"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(element.value as? String)
        XCTAssertLessThanOrEqual(value.utf8.count, 4_096)
        let data = try XCTUnwrap(value.data(using: .utf8))
        let current = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["itemToken", "attemptToken"] {
            XCTAssertNotNil((current[key] as? String).flatMap(UUID.init(uuidString:)))
        }
        return current
    }

    /// Both Watch Two gates use the same real pair, independent source checks,
    /// and audio-control contract without fixtures, source activation or resets.
    private func prepareRealWatchTwo() throws -> (paneOne: XCUIElement, paneTwo: XCUIElement) {
        let watchTwo = app.buttons["home-watch-two"]
        guard watchTwo.waitForExistence(timeout: 15) else {
            throw XCTSkip("The current production selection does not offer two eligible matches on this device.")
        }
        try reveal(watchTwo)
        tap(watchTwo)
        XCTAssertTrue(app.buttons["multiview-cancel-selection"].waitForExistence(timeout: 5),
                      "Watch Two did not enter its selection mode")
        let candidates = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "multiview-candidate-"
        ))
        for _ in 0..<6 {
            if candidates.count >= 2 { break }
            let scroll = visibleContentScroll
            if scroll.exists { scroll.swipeUp() }
        }
        captureEvidence(surface: "Production Watch Two candidate selection")
        guard waitUntil(timeout: 5, { candidates.count >= 2 }) else {
            let cancel = app.buttons["multiview-cancel-selection"]
            if cancel.isHittable { tap(cancel) }
            throw XCTSkip("Fewer than two real production candidates were available; no synthetic matches were injected.")
        }
        let visible = candidates.allElementsBoundByIndex.filter { $0.isHittable }
        let firstID = (visible.first ?? candidates.element(boundBy: 0)).identifier
        let secondID = (visible.dropFirst().first ?? candidates.element(boundBy: 1)).identifier
        XCTAssertNotEqual(firstID, secondID)
        let first = app.buttons[firstID]
        let second = app.buttons[secondID]
        try reveal(first)
        tap(first)
        try reveal(second)
        tap(second)
        XCTAssertTrue(waitUntil(timeout: 5) {
            first.isSelected && second.isSelected
                && self.app.staticTexts["2 of 2 selected"].exists
        })
        let start = app.buttons["multiview-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isEnabled)
        tap(start)

        let paneOne = app.buttons["multiview-source-1"]
        let paneTwo = app.buttons["multiview-source-2"]
        XCTAssertTrue(paneOne.waitForExistence(timeout: 45), "Production panel 1 did not expose its own source control")
        XCTAssertTrue(paneTwo.waitForExistence(timeout: 10), "Production panel 2 did not expose its own source control")
        endSurface = "Production Watch Two"
        let originalTwo = paneTwo.value as? String
        let switchedOne = try selectAlternateSource(in: paneOne)
        XCTAssertEqual(paneTwo.value as? String, originalTwo,
                       "Changing production pane 1 changed pane 2's source")
        let selectedOne = paneOne.value as? String
        let switchedTwo = try selectAlternateSource(in: paneTwo)
        XCTAssertEqual(paneOne.value as? String, selectedOne,
                       "Changing production pane 2 changed pane 1's source")
        navigationTimings.append("Real alternate source selection: pane1=\(switchedOne), pane2=\(switchedTwo); false is unavailable, not qualification")

        let audioTwo = app.buttons["multiview-audio-2"]
        XCTAssertTrue(audioTwo.isHittable)
        XCTAssertTrue(waitUntil(timeout: 15) { audioTwo.isEnabled },
                      "The selected real pane cannot currently receive audio")
        tap(audioTwo)
        XCTAssertTrue(audioTwo.label.localizedCaseInsensitiveContains("Audio playing"))
        XCTAssertTrue(app.buttons["multiview-audio-1"].label.localizedCaseInsensitiveContains("Listen"))
        return (paneOne, paneTwo)
    }

    /// Real catalog and real source resolution; unlike the fixture routing test,
    /// this gives an app-scoped trace a genuine bounded production workload.
    /// Presented controls/surfaces do not establish video, bitrate, or audio.
    func testPhysicalProductionWatchTwoControlsAndBoundedSoak() throws {
        let (paneOne, paneTwo) = try prepareRealWatchTwo()
        let deadline = Date().addingTimeInterval(90)
        var changedLayout = false
        var scalarSamples: [[String: Any]] = []
        var availableNativeHooks: [(pane: Int, element: XCUIElement)] = []
        // The 136 WebKit soak repeatedly traversed the whole AX tree for two
        // absent native hooks. Discover once, retain only an available native
        // measurement, and keep unavailable/Web panes explicitly unknown.
        for pane in 1...2 {
            let hook = app.descendants(matching: .any)["native-measurement-pane-\(pane)"].firstMatch
            let sample = nativeScalarMeasurement(in: pane, element: hook)
            scalarSamples.append(sample)
            if sample["measurementAvailable"] as? Bool == true {
                availableNativeHooks.append((pane, hook))
            }
        }
        var nextControlCheck = Date()
        var nextNativeSample = Date().addingTimeInterval(10)
        while Date() < deadline {
            if Date() >= nextControlCheck {
                XCTAssertEqual(app.state, .runningForeground)
                XCTAssertTrue(paneOne.exists && paneTwo.exists,
                              "Watch Two lost its independent source controls during the production soak")
                nextControlCheck = Date().addingTimeInterval(5)
            }
            if Date() >= nextNativeSample {
                var stillAvailable: [(pane: Int, element: XCUIElement)] = []
                for hook in availableNativeHooks {
                    let sample = nativeScalarMeasurement(in: hook.pane, element: hook.element)
                    scalarSamples.append(sample)
                    if sample["measurementAvailable"] as? Bool == true {
                        stillAvailable.append(hook)
                    }
                }
                // A legitimate native-to-Web failover can remove this hook.
                // Record the first unknown sample, then stop probing it; this
                // soak never reacquires or treats fallback UI as native proof.
                availableNativeHooks = stillAvailable
                nextNativeSample = Date().addingTimeInterval(10)
            }
            if !changedLayout, deadline.timeIntervalSinceNow < 15 {
                let layout = app.buttons["multiview-layout"]
                XCTAssertTrue(layout.exists && layout.isHittable,
                              "The two-match layout control is unavailable for the physical landscape gate")
                let previous = try XCTUnwrap(layout.value as? String)
                XCTAssertTrue(["Equal", "Focus"].contains(previous))
                tap(layout)
                let expected = previous == "Equal" ? "Focus" : "Equal"
                XCTAssertTrue(waitUntil(timeout: 5) { layout.value as? String == expected },
                              "The two-match layout did not change")
                changedLayout = true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(paneOne.exists && paneTwo.exists,
                      "Watch Two lost its independent source controls at the end of the production soak")
        XCTAssertTrue(changedLayout, "The required layout transition was not exercised")
        navigationTimings.append("Full 90-second production soak; foreground/source controls sampled about every 5 seconds, available native hooks about every 10 seconds. Unavailable/Web panes remain unknown; not continuous liveness, audible playback or two decoded panes proof.")
        let samplesData = try JSONSerialization.data(withJSONObject: scalarSamples, options: [.sortedKeys])
        let samples = XCTAttachment(data: samplesData, uniformTypeIdentifier: "public.json")
        samples.name = "Watch Two native scalar samples; absent or WebKit data is unknown"
        samples.lifetime = .keepAlways
        add(samples)
        captureEvidence(surface: "Production Watch Two after bounded soak; scalar logs are separate from UI proof")
        capturedFocusedEnd = true
        let close = app.buttons["multiview-close"]
        XCTAssertTrue(close.exists && close.isHittable)
        tap(close)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !paneOne.exists && !paneTwo.exists && self.app.buttons["tab-home"].exists
        })
    }

    /// Additional interference canary, not a replacement for the sampled
    /// 90-second gate or native-video qualification. No AX/state/screenshot
    /// requests occur during the full passive interval.
    func testPhysicalProductionWatchTwoPassive120SecondCanary() throws {
        let (paneOne, paneTwo) = try prepareRealWatchTwo()
        let started = Date()
        let deadline = started.addingTimeInterval(120)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(1)))
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 120,
                                    "The full passive interval was not completed")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(paneOne.exists && paneTwo.exists,
                      "Watch Two lost its independent source controls after the passive canary")
        let layout = app.buttons["multiview-layout"]
        XCTAssertTrue(layout.exists && layout.isHittable,
                      "The two-match layout control is unavailable after the passive canary")
        let previous = try XCTUnwrap(layout.value as? String)
        XCTAssertTrue(["Equal", "Focus"].contains(previous))
        tap(layout)
        let expected = previous == "Equal" ? "Focus" : "Equal"
        XCTAssertTrue(waitUntil(timeout: 5) { layout.value as? String == expected },
                      "The two-match layout did not change after the passive canary")
        navigationTimings.append("Additional full 120-second passive Watch Two canary: no intermediate AX, app-state or screenshot polling. Final foreground/source controls, layout transition and Close are required; not equivalent to the sampled 90-second gate, continuous liveness, audible playback or two decoded panes proof.")
        captureEvidence(surface: "Production Watch Two after separate passive 120-second canary; final controls only")
        capturedFocusedEnd = true
        let close = app.buttons["multiview-close"]
        XCTAssertTrue(close.exists && close.isHittable)
        tap(close)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !paneOne.exists && !paneTwo.exists && self.app.buttons["tab-home"].exists
        })
    }

    private func nativeScalarMeasurement(in pane: Int, element: XCUIElement) -> [String: Any] {
        let unavailable: [String: Any] = ["pane": pane, "measurementAvailable": false, "accessLogAvailable": false]
        guard element.exists, let value = element.value as? String,
              let data = value.data(using: .utf8), data.count <= 4_096,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A web pane, absent native layer, or inaccessible hook is unknown;
            // source controls existing is not substitute bandwidth/video proof.
            return unavailable
        }
        let scalars: Set<String> = [
            "measurementAvailable", "pane", "uptimeSeconds", "thermalState", "readyForDisplay",
            "currentTimeSeconds", "rate", "timeControlStatus", "itemStatus", "presentationWidth",
            "presentationHeight", "renderedPixelWidth", "renderedPixelHeight", "accessLogAvailable",
            "accessLogEventCount", "accessLogEventIndex", "bytesTransferred", "transferDurationSeconds",
            "observedBitrate", "indicatedBitrate", "droppedVideoFrames", "stalls"
        ]
        var snapshot = unavailable
        for key in scalars {
            if let number = raw[key] as? NSNumber, number.doubleValue.isFinite,
               number.doubleValue >= 0, number.doubleValue <= 9_007_199_254_740_991 {
                snapshot[key] = number
            } else if raw[key] is NSNull {
                snapshot[key] = NSNull()
            }
        }
        // No arbitrary string fields can enter the local attachment. These two
        // IDs are minted by Fotty, not AVFoundation/provider session identifiers.
        for key in ["itemToken", "attemptToken"] {
            snapshot[key] = (raw[key] as? String).flatMap(UUID.init(uuidString:))?.uuidString as Any? ?? NSNull()
        }
        return snapshot
    }

    private func selectAlternateSource(in pane: XCUIElement) throws -> Bool {
        let current = try XCTUnwrap(pane.value as? String)
        let next = current == "Source 1" ? "Source 2" : "Source 1"
        tap(pane)
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", next)).firstMatch
        guard waitUntil(timeout: 5, { choice.exists && choice.isHittable }) else {
            // Keep the independent-control/soak gate running when the live
            // provider currently offers only one source. Re-select the existing
            // menu choice to dismiss it; do not manufacture an alternate.
            let existing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", current)).firstMatch
            guard existing.exists, existing.isHittable else {
                throw XCTSkip("No current or alternate production source choice is selectable; the bounded soak cannot proceed.")
            }
            tap(existing)
            return false
        }
        tap(choice)
        XCTAssertTrue(waitUntil(timeout: 5) { pane.value as? String == next },
                      "The production pane did not select the requested independent source")
        return true
    }

    private var player: XCUIElement {
        app.descendants(matching: .any)["live-player"].firstMatch
    }

    private var searchSurface: XCUIElement {
        app.descendants(matching: .any)["global-sports-search"].firstMatch
    }

    private var sourceRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "broadcast-source-"))
    }

    private func selectTab(_ identifier: String, surface: String) throws {
        let done = app.buttons["settings-done"]
        if identifier == "tab-settings" {
            // Settings is a sheet opened from Home's gear button.
            if !done.exists {
                try selectTab("tab-home", surface: "Home before \(surface)")
                let gear = app.buttons["home-settings"].firstMatch
                XCTAssertTrue(gear.waitForExistence(timeout: 10), "Home's Settings gear is missing")
                tap(gear)
                XCTAssertTrue(done.waitForExistence(timeout: 5), "Settings sheet did not open")
            }
            endSurface = surface
            return
        }
        let tab = tabControl(identifier)
        if !(tab.exists && tab.isHittable) {
            // Settings is open over the tabs. A page pushed inside it (e.g.
            // Sports continuity) goes Back first, then Done closes Settings.
            if !done.exists, let back = app.navigationBars.buttons.allElementsBoundByIndex.first(where: \.isHittable) {
                back.tap()
            }
            if done.waitForExistence(timeout: 3) { tap(done) }
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        let started = Date()
        tap(tab)
        XCTAssertTrue(waitUntil(timeout: 5) { tab.isSelected && self.app.state == .runningForeground },
                      "Tab navigation did not respond: \(surface)")
        endSurface = surface
        navigationTimings.append("\(surface) selected: \(Int(Date().timeIntervalSince(started) * 1_000)) ms")
    }

    private func tabControl(_ identifier: String) -> XCUIElement {
        // iPadOS exposes both the semantic wrapper and its leaf button with
        // the same identifier. The wrapper exists but is not a touch target.
        app.buttons.matching(identifier: identifier).allElementsBoundByIndex
            .last(where: { $0.isHittable })
            ?? app.buttons.matching(identifier: identifier).element(boundBy: 0)
    }

    private func openSearch() throws {
        let search = app.buttons["home-search"]
        try reveal(search)
        tap(search)
        XCTAssertTrue(searchSurface.waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        endSurface = "Production Search"
    }

    private func replaceSearchText(with value: String) throws {
        let field = searchSurface.searchFields.firstMatch
        let existing = field.value as? String ?? ""
        if existing != field.placeholderValue, !existing.isEmpty {
            // A real138 receipt retained only "cri" after one complete
            // typeText("cricket") following Select All. Exercise the native
            // Clear route and verify it, rather than repair partial suffixes
            // or change production query/focus behavior for an XCTest failure.
            tap(field)
            XCTAssertTrue(waitUntil(timeout: 5) {
                field.exists && field.isEnabled && field.isHittable
                    && self.app.keyboards.firstMatch.exists
            }, "The retained Search query could not acquire native keyboard focus")
            let clear = field.buttons["Clear text"].firstMatch
            XCTAssertTrue(waitUntil(timeout: 3) {
                clear.exists && clear.isHittable
            }, "Native Clear text is unavailable; query replacement cannot qualify")
            tap(clear)
            XCTAssertTrue(waitUntil(timeout: 3) {
                let current = field.value as? String ?? ""
                return current.isEmpty || current == field.placeholderValue
            }, "Native Clear text did not remove the complete retained query")
        }
        // On the physical iPad, native Clear completes but dismisses the
        // keyboard. Reacquire the actual field just as a user would before
        // typing; clearing alone is not a keyboard-focus receipt.
        // A visible keyboard can belong to a previous native focus owner.
        // Explicitly reacquire this presented field after Clear, not just when
        // all keyboards disappear. Keep the one complete typing command and
        // exact-query assertion; never repair a dropped suffix.
        tap(field)
        XCTAssertTrue(waitUntil(timeout: 5) {
            field.exists && field.isEnabled && field.isHittable
                && self.app.keyboards.firstMatch.exists
        },
                      "The Search field/native keyboard became unavailable before committed input")
        // Complete-string typing qualifies exact committed queries, not
        // per-prefix input stress or isolated latency. Each ordinary native
        // interaction remains subject to XCTest's real idle waits.
        // Apple's element-scoped typeText requires keyboard focus on this
        // element (or its descendant) and fails if focus moved elsewhere. Do
        // not repair suffixes or rewrite the app's query through a test hook.
        field.typeText(value)
        let committed = waitUntil(timeout: 3) { field.value as? String == value }
        let receipt = XCTAttachment(string: "One native complete-query typing command. Expected=\(value.prefix(120)); observed=\((field.value as? String ?? "").prefix(120)); exact match=\(committed). No suffix repair or synthetic query mutation.")
        receipt.name = "Native Search committed-query receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(committed,
                      "Search lost committed input; partial text cannot qualify")
    }

    private func dismissSearchKeyboard(preservingQuery query: String) throws {
        XCTAssertTrue(searchSurface.exists)
        if app.keyboards.firstMatch.exists {
            let dismiss = app.keyboards.buttons["Hide keyboard"].firstMatch
            XCTAssertTrue(dismiss.exists && dismiss.isHittable,
                          "The native keyboard-dismiss control is unavailable")
            tap(dismiss)
            XCTAssertTrue(waitUntil(timeout: 5) { !self.app.keyboards.firstMatch.exists })
        }
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, query,
                       "The harness changed the committed Search query")
    }

    private func realWatchControl() throws -> XCUIElement {
        // Prefer a catalog-supported current event. A named channel fallback
        // remains a channel; this test never invents the game it is airing.
        _ = app.buttons.matching(identifier: "home-watch-now").firstMatch.waitForExistence(timeout: 15)
        for _ in 0..<4 {
            let candidates = app.buttons.matching(identifier: "home-watch-now").allElementsBoundByIndex
            if let watch = candidates.first(where: { $0.isHittable && $0.isEnabled }) { return watch }
            let scroll = visibleContentScroll
            if scroll.exists { scroll.swipeDown() }
        }
        try openSearch()
        try replaceSearchText(with: "Willow")
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.app.searchFields.firstMatch.value as? String == "Willow"
                && !self.app.staticTexts["Searching…"].exists
        })
        let watch = searchSurface.buttons["search-result-admin-willow-cricket"]
        guard watch.waitForExistence(timeout: 15) else {
            throw XCTSkip("No currently watchable production event or explicit Willow channel was available.")
        }
        // A swipe over keyboard-covered Search can hit keys instead of content
        // on the physical iPad. Use the same native dismissal/query invariant
        // as the exact-fixture CS path before trying to reveal a real channel.
        try dismissSearchKeyboard(preservingQuery: "Willow")
        try reveal(watch)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Willow",
                       "Revealing the real channel changed its Search query")
        return watch
    }

    private func openRealPlayback() throws {
        let watch = try realWatchControl()
        let started = Date()
        tap(watch)
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.player.exists
                || self.app.descendants(matching: .any)["stream-resolution-panel"].exists
                || self.app.alerts["Stream Not Available"].exists
        }, "Watch produced no prompt lookup/player feedback")
        navigationTimings.append("Watch feedback: \(Int(Date().timeIntervalSince(started) * 1_000)) ms")
        XCTAssertTrue(player.waitForExistence(timeout: 40), "Production lookup did not present a player")
        endSurface = "Production single player"
    }

    private func waitForStartupUI(timeout: TimeInterval) throws {
        XCTAssertTrue(waitUntil(timeout: timeout) {
            self.player.exists
                && !self.app.descendants(matching: .any)["stream-loading"].exists
                && !self.app.descendants(matching: .any)["playback-error"].exists
        }, "The production player did not finish startup without a terminal error")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func revealPlayerChrome() throws {
        if app.buttons["close-live-player"].isHittable { return }
        XCTAssertTrue(player.exists)
        // A real surface tap may also pause a web provider. Restore explicit
        // Play below if needed; never infer audible/video success from chrome.
        tap(player)
        XCTAssertTrue(app.buttons["close-live-player"].waitForExistence(timeout: 5))
        let web = app.buttons["web-play-pause"]
        if web.exists, web.label.localizedCaseInsensitiveContains("Play broadcast") {
            tap(web)
        }
    }

    private func openSources(requirePreviouslyObservedPicker: Bool = false) throws {
        try revealPlayerChrome()
        let sources = currentSingleSourcePicker
        guard sources.waitForExistence(timeout: 3), sources.isHittable else {
            if requirePreviouslyObservedPicker {
                XCTFail("The previously observed source picker became unavailable during the CS control gate")
                return
            }
            throw XCTSkip("The current real source has no alternative source picker.")
        }
        tap(sources)
        XCTAssertTrue(sourceRows.firstMatch.waitForExistence(timeout: 5))
        endSurface = "Production broadcast source picker"
    }

    private var currentSingleSourcePicker: XCUIElement {
        let managed = app.buttons["viewing-sources"]
        return managed.exists ? managed : app.buttons["Choose broadcast source"].firstMatch
    }

    private func closeSourceSheetIfPresent() throws {
        let close = app.buttons["Close broadcast sources"]
        if close.exists { tap(close) }
        XCTAssertTrue(waitUntil(timeout: 5) { !close.exists })
    }

    private func closePlayer() throws {
        try closeSourceSheetIfPresent()
        try revealPlayerChrome()
        tap(app.buttons["close-live-player"])
        XCTAssertTrue(waitUntil(timeout: 5) { !self.player.exists && self.app.buttons["tab-home"].exists })
        endSurface = "Home after player dismissal"
    }

    private func readProvenStartsThroughExistingSettings() throws -> Int {
        try selectTab("tab-settings", surface: "Settings")
        if !app.staticTexts["Proven starts"].exists {
            let privacy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Privacy")).firstMatch
            try reveal(privacy)
            tap(privacy)
            let quality = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Quality & Diagnostics")).firstMatch
            try reveal(quality)
            tap(quality)
        }
        let label = app.staticTexts["Proven starts"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let values = app.staticTexts.allElementsBoundByIndex.filter {
            Int($0.label) != nil && $0.frame.minY >= label.frame.minY - 5
                && $0.frame.minY <= label.frame.maxY + 28
                && $0.frame.minX >= label.frame.minX
        }.sorted { abs($0.frame.midY - label.frame.midY) < abs($1.frame.midY - label.frame.midY) }
        guard let value = values.first, let number = Int(value.label) else {
            throw XCTSkip("Existing local quality counter is inaccessible; loading completion alone cannot qualify decoded playback.")
        }
        endSurface = "Private on-device Playback Evidence"
        return number
    }

    private func reveal(_ element: XCUIElement) throws {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            let scroll = visibleContentScroll
            guard scroll.exists else { break }
            if element.exists && element.frame.maxY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The expected production control is not reachable")
    }

    private var visibleContentScroll: XCUIElement {
        let scope: XCUIElement = searchSurface.exists ? searchSurface : app!
        return scope.scrollViews.allElementsBoundByIndex
            .filter { $0.isHittable }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            ?? scope.scrollViews.firstMatch
    }

    private func waitForNativeLayerAndMediaProgress(timeout: TimeInterval) -> Bool {
        nativeLayerAndMediaProgressMeasurement(timeout: timeout) != nil
    }

    private func nativeLayerAndMediaProgressMeasurement(timeout: TimeInterval,
                                                       evidenceName: String? = nil) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        var previous: [String: Any]?
        var sampleCount = 0
        var lastSampleAt = Date.distantPast
        var lastSampleAttempt: String?
        while Date() < deadline {
            let element = app.descendants(matching: .any)["native-playback-measurement"].firstMatch
            if element.exists, let value = element.value as? String,
               let data = value.data(using: .utf8), data.count <= 4_096,
               let current = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let item = current["itemToken"] as? String, UUID(uuidString: item) != nil,
               let attempt = current["attemptToken"] as? String, UUID(uuidString: attempt) != nil,
               let time = current["currentTimeSeconds"] as? Double, time.isFinite {
                // Keep at most six bounded, local scalar receipts, including
                // unready attempts. Identity changes make fallback explicit;
                // a truncated AX dump must not hide the failed source's state.
                let sampledAt = Date()
                if let evidenceName, sampleCount < 6,
                   lastSampleAttempt != attempt || sampledAt.timeIntervalSince(lastSampleAt) >= 5 {
                    sampleCount += 1
                    attachNativeMeasurementScalars(current, name: "\(evidenceName) sample \(sampleCount)")
                    lastSampleAt = sampledAt
                    lastSampleAttempt = attempt
                }
                if current["readyForDisplay"] as? Bool == true,
                   (current["renderedPixelWidth"] as? Double ?? 0) > 0,
                   (current["renderedPixelHeight"] as? Double ?? 0) > 0 {
                    if let previous, previous["itemToken"] as? String == item,
                       previous["attemptToken"] as? String == attempt,
                       let oldTime = previous["currentTimeSeconds"] as? Double,
                       time > oldTime + 0.1 { return current }
                    previous = current
                } else {
                    previous = nil
                }
            } else {
                previous = nil
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return nil
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(waitUntil(timeout: 5) { element.exists && element.isHittable },
                      "Cannot tap a missing or covered control")
        element.tap()
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    private func captureEvidence(surface: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = surface
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: String(app.debugDescription.prefix(120_000)))
        hierarchy.name = "Focused \(surface) accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func widgetGalleryControl(_ springboard: XCUIApplication, labels: [String],
                                      timeout: TimeInterval) -> XCUIElement? {
        var found: XCUIElement?
        _ = waitUntil(timeout: timeout) {
            for label in labels {
                for element in [springboard.buttons[label].firstMatch, springboard.staticTexts[label].firstMatch] {
                    if element.exists && element.isHittable { found = element; return true }
                }
            }
            return false
        }
        return found
    }

    private func widgetGalleryElementIsVisible(_ element: XCUIElement, in springboard: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && !frame.isNull && springboard.frame.intersects(frame)
    }

    private func captureSportsWidgetGalleryEvidence(_ springboard: XCUIApplication, stage: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Sports widget gallery: \(stage)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Scalar receipts from relevant native controls, not a full SpringBoard
        // AX dump (which can include every icon and be expensive on this Mac).
        var lines = ["Stage: \(stage)", "SpringBoard state: \(springboard.state.rawValue)"]
        let labels = ["Options", "Open Windows", "Edit Home Screen", "Edit", "Done", "Close", "Cancel", "Add Widget", "Add Widgets",
                      "Fotty Sports Hub", "FottySportsHub", "Fotty", "Your sports plan",
                      "Save a match in Fotty", "Open Fotty for your plan"]
        for label in labels {
            for element in [springboard.buttons[label].firstMatch, springboard.staticTexts[label].firstMatch] where element.exists {
                lines.append("type=\(element.elementType.rawValue); label=\(String(element.label.prefix(250))); id=\(String(element.identifier.prefix(150))); frame=\(element.frame); hittable=\(element.isHittable)")
            }
        }
        let search = springboard.searchFields.firstMatch
        if search.exists { lines.append("Search field: \(String(search.label.prefix(150))); value=\(String(String(describing: search.value).prefix(150)))") }
        let hierarchy = XCTAttachment(string: String(lines.joined(separator: "\n").prefix(12_000)))
        hierarchy.name = "Bounded sports widget gallery native hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func restoreHomeAfterWidgetGallery(_ springboard: XCUIApplication) {
        if let close = widgetGalleryControl(springboard, labels: ["Close", "Cancel"], timeout: 0.3) { close.tap() }
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        if let done = widgetGalleryControl(springboard, labels: ["Done"], timeout: 0.3) { done.tap() }
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        app.activate()
        if !waitUntil(timeout: 5, { self.app.state == .runningForeground }) {
            record(XCTIssue(type: .assertionFailure, compactDescription: "Fotty did not return to the foreground after dismissing the read-only widget gallery."))
        }
    }
}

/// Explicit Jet-only acceptance for the November Watch/Retry repair. These
/// checks use real production choices and leave source preferences untouched.
final class WatchRetry220PhysicalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The forced drill permits two primary hold windows and one backup
        // window in addition to bounded native startup and recovery.
        executionTimeAllowance = ProcessInfo.processInfo.environment["FOTTY_FORCE_SOURCE_FAILURE"] == "1" ? 660 : 480
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Owner-approved physical iPad gate only")
        #else
        guard ProcessInfo.processInfo.environment["FOTTY_WATCH220_PHYSICAL"] == "1",
              ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil,
              (UIDevice.current.userInterfaceIdiom == .pad
                || ProcessInfo.processInfo.environment["FOTTY_WATCH_PHONE_PHYSICAL"] == "1") else {
            throw XCTSkip("Requires the explicit owner-device gate; phone testing needs its separate opt-in")
        }
        let env = ProcessInfo.processInfo.environment
        let modes = ["FOTTY_VERIFY_PAUSE_ONLY", "FOTTY_FORCE_SOURCE_FAILURE", "FOTTY_VERIFY_ALTERNATE"]
        XCTAssertLessThanOrEqual(modes.filter { env[$0] == "1" }.count, 1,
            "Choose only one physical operation: Pause/Play, forced outage, or manual alternate.")
        app = XCUIApplication(bundleIdentifier: "com.jelani.Fotty")
        app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        if env["FOTTY_FORCE_SOURCE_FAILURE"] == "1", let id = env["FOTTY_FIXTURE_GATE_ID"] {
            app.launchEnvironment["FOTTY_PRIVATE_OUTAGE_FIXTURE"] = id
            if env["FOTTY_TIMED_INDEPENDENT_DRILL"] == "1" {
                app.launchEnvironment["FOTTY_DRILL_ORDINARY_SELECTION"] = "1"
            }
        }
        if name.contains("testFS1AutomaticStationRecovery") {
            app.launchEnvironment["FOTTY_PRIVATE_OUTAGE_FIXTURE"] = "sports-channel:fox-sports-1-us"
        } else if name.contains("testSkyCricketAutomaticStationRecovery") {
            app.launchEnvironment["FOTTY_PRIVATE_OUTAGE_FIXTURE"] = "sports-channel:sky-sports-cricket"
        }
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "tab-tv").firstMatch.waitForExistence(timeout: 20))
        let tv = app.buttons.matching(identifier: "tab-tv").allElementsBoundByIndex.last(where: { $0.isHittable })
        try XCTUnwrap(tv).tap()
        #endif
    }

    override func tearDownWithError() throws {
        guard app != nil else { return }
        let trace = app.staticTexts["private-recovery-trace"]
        if trace.exists { attach("Recovery trace: " + (trace.value as? String ?? "")) }
        if app.buttons["Close broadcast sources"].exists { app.buttons["Close broadcast sources"].tap() }
        if app.buttons["close-live-player"].exists { app.buttons["close-live-player"].tap() }
        app.terminate()
    }

    func testFoxSportsOneStationThroughWatch() throws {
        try verifyNewStation("Fox Sports 1", route: "TV24")
    }

    func testFS1AutomaticStationRecovery() throws {
        try verifyAutomaticStationRecovery("Fox Sports 1", primaryRoute: "TV24")
    }

    func testSkyCricketAutomaticStationRecovery() throws {
        try verifyAutomaticStationRecovery("Sky Sports Cricket", primaryRoute: "TV10")
    }

    private func verifyAutomaticStationRecovery(_ title: String, primaryRoute: String) throws {
        try scrollToWatch(title)
        try openPicker(timeout: 75)
        let primary = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "broadcast-source-", primaryRoute)).firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 12))
        if !primary.isSelected { primary.tap() }
        closeSourceSheet()
        let owner = try XCTUnwrap(waitForReady(timeout: 90))
        XCTAssertEqual(try selectedRoute(), primaryRoute)
        capture(title + " original primary picture")
        let fault = app.buttons["private-match-outage-drill"]
        XCTAssertTrue(fault.waitForExistence(timeout: 8))
        fault.tap()
        let marker = app.staticTexts["private-match-outage-route"]
        XCTAssertTrue(wait(90) { marker.exists && marker.label == "Alternative" })
        let restored = try XCTUnwrap(waitForReady(timeout: 90, excludingAttempt: owner["attemptToken"] as? String))
        let route = try selectedRoute()
        XCTAssertTrue(route.hasPrefix("CS"))
        try hold(owner: restored, programme: title + " automatic replacement", route: route)
    }

    func testSkyMainStationThroughWatch() throws {
        try scrollToWatch("Sky Sports Main Event")
        let ready = try XCTUnwrap(waitForReady(timeout: 90))
        let route = try selectedRoute()
        XCTAssertTrue(route.hasPrefix("CS"))
        try hold(owner: ready, programme: "Sky Sports Main Event", route: route)
    }

    private func scrollToWatch(_ title: String) throws {
        let station = app.buttons.matching(NSPredicate(format: "label == %@", "Watch " + title)).firstMatch
        for _ in 0..<7 where !station.exists || !station.isHittable { app.swipeUp() }
        try openStation(title)
    }

    func testCricketGoldStationThroughWatch() throws {
        try verifyNewStation("Cricket Gold", route: "TV23")
    }

    func testFIFAPlusStationThroughWatch() throws {
        try verifyNewStation("FIFA+", route: "TV21")
    }

    func testFIFAPlusWomenStationThroughWatch() throws {
        try verifyNewStation("FIFA+ Women", route: "TV22")
    }

    private func verifyNewStation(_ title: String, route: String) throws {
        let station = app.buttons.matching(NSPredicate(format: "label == %@", "Watch " + title)).firstMatch
        for _ in 0..<7 where !station.exists || !station.isHittable { app.swipeUp() }
        try openStation(title)
        let ready = try XCTUnwrap(waitForReady(timeout: 75), "No advancing native station video")
        XCTAssertEqual(try selectedRoute(), route)
        try hold(owner: ready, programme: title, route: route)
    }

    func testWillowWatchAcknowledgementAndNinetySecondNativeHold() throws {
        try openStation("Willow Cricket")
        // The station can also expose CS. Choose TV1 explicitly so its failure
        // cannot be credited to a healthy alternative from the same channel.
        try openPicker(timeout: 75)
        let tv = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@",
            "broadcast-source-", "TV1")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 12), "Willow TV1 is absent from its existing source picker")
        if !tv.isSelected || tv.label.hasSuffix(", Try again") { tv.tap() }
        closeSourceSheet()
        let ready = try XCTUnwrap(waitForReady(timeout: 100), "Selected TV1 did not reach ready native video")
        XCTAssertEqual(try selectedRoute(), "TV1", "A fallback is not proof of TV1")
        try hold(owner: ready, programme: "Willow Cricket", route: "TV1")
    }

    /// The public ID/label selects an existing live match. It cannot supply a fixture or a stream.
    func testCurrentNamedMatchThroughWatch() throws {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["FOTTY_FIXTURE_GATE_ID"], let title = env["FOTTY_FIXTURE_GATE_TITLE"],
              !id.isEmpty, !title.isEmpty else { throw XCTSkip("No independently verified live fixture supplied") }
        let home = app.buttons.matching(identifier: "tab-home").allElementsBoundByIndex.last(where: { $0.isHittable })
        try XCTUnwrap(home).tap()
        let more = app.buttons["home-more-live"].firstMatch
        var expanded = false
        defer {
            let trace = app.staticTexts["private-recovery-trace"]
            if trace.exists { attach("Final recovery trace: " + (trace.value as? String ?? "")) }
            if app.buttons["close-live-player"].isHittable { app.buttons["close-live-player"].tap() }
            if expanded && more.isHittable && more.value as? String == "Expanded" { more.tap() }
        }
        let watch = app.buttons.matching(NSPredicate(format: "identifier IN %@ OR label == %@",
            ["match-start-play-"+id, "match-start-check-streams-"+id], "Watch "+title))
        var found: XCUIElement?
        // XCTest can call a row "hittable" while its centre is covered by the
        // floating tab bar. Reveal it in the content viewport before tapping.
        func visibleTarget(_ element: XCUIElement) -> Bool {
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            let tabs = app.buttons.matching(identifier: "tab-home").allElementsBoundByIndex
                .filter { $0.isHittable }.map(\.frame)
            let lower = tabs.filter { $0.midY > app.frame.midY }.map(\.minY).min() ?? app.frame.maxY
            return frame.midY > app.frame.minY + 60 && frame.maxY < lower - 8
        }
        func scrollContent() {
            let scroll = app.scrollViews.allElementsBoundByIndex.first { $0.isHittable && $0.frame.height > 200 }
            if let scroll { scroll.swipeUp() } else { app.swipeUp() }
        }
        for _ in 0..<8 {
            let candidates = watch.allElementsBoundByIndex.filter { visibleTarget($0) }
            if candidates.count == 1 { found = candidates[0]; break }
            if !expanded && visibleTarget(more) && more.value as? String == "Collapsed" {
                more.tap()
                expanded = more.value as? String == "Expanded"
            } else { scrollContent() }
        }
        // A personal Home can legitimately omit this sport. Use the existing full
        // schedule without modifying interests or treating an unrelated tile as the fixture.
        if found == nil {
            let tab = app.buttons.matching(identifier: "tab-arena").allElementsBoundByIndex.last { $0.isHittable }
            try XCTUnwrap(tab).tap()
            attach("Named event not visible on personal Home; trying its Watch action on Matchday.")
            for _ in 0..<9 {
                let candidates = watch.allElementsBoundByIndex.filter { visibleTarget($0) }
                if candidates.count == 1 { found = candidates[0]; break }
                scrollContent()
            }
        }
        let watchButton = try XCTUnwrap(found, "No unique accessible Watch action for the named fixture")
        let watchStart = ProcessInfo.processInfo.systemUptime
        watchButton.tap()
        if env["FOTTY_VERIFY_RETURN_PICK"] == "1", let requested = env["FOTTY_RETURN_WATCH_SOURCE"] {
            try openPicker(timeout: 75)
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@",
                "broadcast-source-", requested)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 30), "Requested alternative was not listed")
            if !row.isSelected { row.tap() }
            closeSourceSheet()
            attach("Viewer chose " + requested + " on the first visit; the return Watch is automatic.")
        }
        if let requested = env["FOTTY_RESUME_SOURCE"] {
            try openPicker(timeout: 75)
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@",
                "broadcast-source-", requested)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 30), "Requested resume delivery is absent")
            if !row.isSelected { row.tap() }
            closeSourceSheet()
        }
        let ready = try XCTUnwrap(waitForReady(timeout: 100), "Named fixture did not reach advancing native video")
        if env["FOTTY_TIMED_INDEPENDENT_DRILL"] == "1" {
            let elapsed = ProcessInfo.processInfo.systemUptime - watchStart
            capture("Initial picture at " + String(format: "%.2fs after Watch", elapsed))
        }
        let route = try selectedRoute()
        if let requested = env["FOTTY_RESUME_SOURCE"] {
            guard route == requested else {
                XCTFail("Requested resume delivery " + requested + " did not remain selected; actual " + route)
                return
            }
        }
        if env["FOTTY_VERIFY_RETURN_PICK"] == "1" {
            var stable = route
            do {
                try hold(owner: ready, programme: title, route: stable)
            } catch let loss as HoldFailure where loss.natural {
                attach("First route interrupted before return-Watch check: " + loss.description)
                let backup = try XCTUnwrap(waitForReady(timeout: 100),
                    "Neither the original stream nor a replacement resumed advancing after the stall")
                stable = try selectedRoute()
                try hold(owner: backup, programme: title, route: stable)
            }
            let close = app.buttons["close-live-player"]
            try XCTUnwrap(close.exists && close.isHittable ? close : nil).tap()
            let reopen = try XCTUnwrap(watch.allElementsBoundByIndex.first { $0.isHittable })
            reopen.tap()
            _ = try XCTUnwrap(waitForReady(timeout: 90), "Return Watch did not reach advancing video")
            let next = try selectedRoute()
            attach("Return Watch after sustained playback: " + title + " via " + stable + ", then " + next)
            XCTAssertEqual(next, stable, "Fresh Watch should prefer the still-available sustained delivery")
            capture("Return Watch after sustained playback via " + next)
            return
        }
        if env["FOTTY_VERIFY_PAUSE_ONLY"] == "1" {
            let owner = try XCTUnwrap(waitForReady(timeout: 12, sameOwner: ready),
                "Original source stopped advancing before the transport check.")
            capture("Transport-only named Watch before Pause: " + title + " via " + route)
            try verifyPauseAndResume(owner: owner)
            capture("Transport-only named Watch after Play: " + title + " via " + route)
            attach("FOTTY_VERIFY_PAUSE_ONLY: " + title + " via " + route +
                "; real Watch and Pause/Play on the same AV owner. No 90-second hold or outage proof in this run.")
            return
        }
        let force = env["FOTTY_FORCE_SOURCE_FAILURE"] == "1"
        var unmetPrimaryHold: String?
        if force && env["FOTTY_EARLY_SOURCE_LOSS"] == "1" {
            capture("Initial decoded programme before early fault via " + route)
            attach("Early interruption drill: no primary continuity claim.")
        } else {
            do {
                try hold(owner: ready, programme: title, route: route)
            } catch let interruption as HoldFailure where interruption.natural {
                unmetPrimaryHold = interruption.description
                if force, waitForReady(timeout: 30, sameOwner: ready) != nil {
                    attach("Starting one fresh primary hold on the same rendering owner after its recorded interruption.")
                    do {
                        try hold(owner: ready, programme: title, route: route)
                        unmetPrimaryHold = nil
                    } catch let retry as HoldFailure where retry.natural {
                        unmetPrimaryHold = retry.description
                    }
                }
            }
        }
        if force {
            var faultOwner = ready
            var faultRoute = route
            if unmetPrimaryHold != nil, waitForReady(timeout: 4, sameOwner: ready) == nil {
                faultOwner = try XCTUnwrap(waitForReady(timeout: 70, excludingAttempt: ready["attemptToken"] as? String),
                    "No advancing replacement after natural interruption")
                faultRoute = try selectedRoute()
                attach("Natural interruption of " + route + "; playback resumed on " + faultRoute + ". Original continuity failure is retained.")
                try hold(owner: faultOwner, programme: title + " following natural interruption", route: faultRoute)
            }
            let fault = app.buttons["private-match-outage-drill"].firstMatch
            XCTAssertTrue(fault.waitForExistence(timeout: 8) && fault.isHittable,
                          "Expected the named fixture's private one-shot AV failure control")
            XCTAssertEqual(try selectedRoute(), faultRoute, "Natural failover must not change which primary is injected.")
            capture("Correct-programme review immediately before controlled primary loss: " + title)
            _ = try XCTUnwrap(waitForReady(timeout: 8, sameOwner: faultOwner),
                "Controlled loss was not exercised: original primary did not resume advancing on its original owner.")
            let faultStart = ProcessInfo.processInfo.systemUptime
            fault.tap()
            let routeMarker = app.staticTexts["private-match-outage-route"].firstMatch
            XCTAssertTrue(wait(100) { routeMarker.exists && routeMarker.label == "Alternative" },
                          "The unavailable primary was not automatically replaced: \(String(describing: routeMarker.value))")
            let recovered = try XCTUnwrap(waitForReady(timeout: 100, excludingAttempt: faultOwner["attemptToken"] as? String, replacingOwner: faultOwner),
                                          "No new advancing native attempt after source failure")
            if env["FOTTY_TIMED_INDEPENDENT_DRILL"] == "1" {
                let elapsed = ProcessInfo.processInfo.systemUptime - faultStart
                capture("Replacement picture at " + String(format: "%.2fs after cut", elapsed))
            }
            let backup = try selectedRoute()
            XCTAssertNotEqual(backup, faultRoute, "A restarted primary is not backup-source recovery")
            try hold(owner: recovered, programme: title, route: backup)
            if env["FOTTY_TIMED_INDEPENDENT_DRILL"] == "1" {
                let receipt = try XCTUnwrap(routeMarker.value as? String)
                attach("Backup provenance after sustained playback: " + receipt)
                XCTAssertTrue(receipt.contains("provenance=different-publisher-and-origin"),
                              "A second route alone cannot establish independent delivery: " + receipt)
            }
            attach("Held one real delivery unavailable using local AV item failures: " + faultRoute + " → " + backup +
                ". No manual replacement. Programme correctness needs independent picture review.")
        } else if env["FOTTY_VERIFY_ALTERNATE"] == "1" {
            try openPicker(timeout: 10)
            let choices = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "broadcast-source-[0-9]+"))
            let alternate = try XCTUnwrap(choices.allElementsBoundByIndex.first { !$0.isSelected && $0.isHittable
                && ($0.value as? String) != route }, "No distinct selectable alternative")
            let nextRoute = try XCTUnwrap(alternate.value as? String)
            alternate.tap()
            closeSourceSheet()
            let nextOwner = try XCTUnwrap(waitForReady(timeout: 75, excludingAttempt: ready["attemptToken"] as? String))
            XCTAssertNotEqual(ready["attemptToken"] as? String, nextOwner["attemptToken"] as? String)
            XCTAssertEqual(try selectedRoute(), nextRoute)
            try hold(owner: nextOwner, programme: title, route: nextRoute)
        } else {
            _ = try XCTUnwrap(waitForReady(timeout: 30, sameOwner: ready),
                "Pause/Play was not exercised: original owner did not resume advancing.")
            try verifyPauseAndResume(owner: ready)
            if env["FOTTY_RESUME_SOURCE"] != nil {
                try hold(owner: ready, programme: title + " after resume", route: route)
            }
        }
        if let unmetPrimaryHold {
            XCTFail("The primary continuity gate remained open after the separate operation: " + unmetPrimaryHold)
        }
    }

    /// Verify intent with the normal transport and AV state after restoring the same surface.
    private func verifyPauseAndResume(owner: [String: Any]) throws {
        func transport(_ label: String) throws {
            let minimize = app.buttons["viewing-minimize"].firstMatch
            XCTAssertTrue(minimize.waitForExistence(timeout: 5) && minimize.isHittable)
            minimize.tap()
            let button = app.buttons.matching(identifier: "viewing-mini-transport").allElementsBoundByIndex
                .first { $0.isHittable && $0.label == label }
            try XCTUnwrap(button, "Missing mini-player transport: " + label).tap()
            let expand = app.buttons.matching(identifier: "viewing-mini-expand").allElementsBoundByIndex.first { $0.isHittable }
            try XCTUnwrap(expand).tap()
        }
        try transport("Pause broadcast")
        XCTAssertTrue(wait(8) { self.measurement()?["timeControlStatus"] as? Int == 0 })
        func pausedTime() throws -> Double {
            let paused = try XCTUnwrap(measurement())
            for key in ["playerToken", "itemToken", "attemptToken"] {
                XCTAssertEqual(try XCTUnwrap(paused[key] as? String), try XCTUnwrap(owner[key] as? String))
            }
            XCTAssertEqual(paused["timeControlStatus"] as? Int, AVPlayer.TimeControlStatus.paused.rawValue)
            return try XCTUnwrap(paused["currentTimeSeconds"] as? Double)
        }
        let t0 = try pausedTime()
        let pauseSeconds = min(60, max(2, Double(ProcessInfo.processInfo.environment["FOTTY_PAUSE_SECONDS"] ?? "2") ?? 2))
        RunLoop.current.run(until: Date().addingTimeInterval(pauseSeconds))
        let t1 = try pausedTime()
        XCTAssertLessThan(abs(t1 - t0), 0.35, "Playback advanced while deliberately paused")
        let resumeStart = ProcessInfo.processInfo.systemUptime
        try transport("Resume broadcast")
        let resumed = try XCTUnwrap(waitForReady(timeout: 15), "Play did not restore advancing native video")
        attach("Resume after " + String(pauseSeconds) + "s paused: " +
            String(format: "%.3fs including native navigation", ProcessInfo.processInfo.systemUptime - resumeStart))
        for key in ["playerToken", "itemToken", "attemptToken"] {
            XCTAssertEqual(try XCTUnwrap(resumed[key] as? String), try XCTUnwrap(owner[key] as? String))
        }
        attach("Real Pause stopped the clock; Play resumed on the same player, item and attempt.")
    }

    private func selectedRoute() throws -> String {
        try openPicker(timeout: 10)
        let rows = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "broadcast-source-[0-9]+"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8))
        let selected = rows.allElementsBoundByIndex.filter { $0.isSelected }
        XCTAssertEqual(selected.count, 1, "The picker must identify exactly one current route")
        let name = try XCTUnwrap((selected.first?.value as? String)
            ?? selected.first?.label.split(separator: ",").first.map(String.init))
        capture("Existing picker: "+name)
        closeSourceSheet()
        return name
    }

    private func openPicker(timeout: TimeInterval) throws {
        let player = app.descendants(matching: .any)["live-player"].firstMatch
        let query = app.buttons.matching(identifier: "viewing-sources")
        XCTAssertTrue(wait(timeout) { player.exists || query.firstMatch.exists })
        if !query.allElementsBoundByIndex.contains(where: { $0.isHittable }), player.isHittable {
            player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        let picker = try XCTUnwrap(query.allElementsBoundByIndex.last(where: { $0.isHittable }))
        picker.tap()
    }

    private func closeSourceSheet() {
        let close = app.buttons["Close broadcast sources"].firstMatch
        if close.exists && close.isHittable { close.tap() }
        XCTAssertTrue(wait(5) { !close.exists }, "Source sheet did not close")
    }

    private struct HoldFailure: Error, CustomStringConvertible, LocalizedError {
        let description: String
        let natural: Bool
        var errorDescription: String? { description }
    }

    private func hold(owner baseline: [String: Any], programme: String, route: String) throws {
        let evidence = programme + " via " + route
        capture(evidence + " before hold")
        var firstUptime: Double?
        var latest: [String: Any]?
        func failure(_ reason: String, natural: Bool = false) -> HoldFailure {
            let fields = ["uptimeSeconds", "currentTimeSeconds", "timeControlStatus", "rate", "accessLogEventIndex", "stalls"]
            let counters = fields.map { key in key + "=" + (latest?[key].map { String(describing: $0) } ?? "unknown") }
            let elapsed = firstUptime.flatMap { start in (latest?["uptimeSeconds"] as? Double).map { $0 - start } }
            let receipt = "\(ISO8601DateFormatter().string(from: Date())) \(evidence) failed hold: \(reason); elapsed=\(elapsed.map { String(format: "%.2f", $0) } ?? "unknown"); " + counters.joined(separator: ", ")
            attach(receipt)
            capture(evidence + " interrupted hold")
            return HoldFailure(description: receipt, natural: natural)
        }
        func sample() throws -> (uptime: Double, media: Double, logIndex: Int?, stalls: Int?) {
            latest = measurement()
            guard let sample = latest else { throw failure("Native measurement unavailable") }
            for key in ["playerToken", "itemToken", "attemptToken"] {
                guard let owner = baseline[key] as? String, sample[key] as? String == owner else {
                    throw failure("Native " + key + " changed during hold")
                }
            }
            guard sample["measurementAvailable"] as? Bool == true, let uptime = sample["uptimeSeconds"] as? Double,
                  uptime.isFinite, let media = sample["currentTimeSeconds"] as? Double, media.isFinite else {
                throw failure("Native owner clock unavailable")
            }
            guard sample["readyForDisplay"] as? Bool == true, (sample["renderedPixelWidth"] as? Double ?? 0) > 0,
                  (sample["renderedPixelHeight"] as? Double ?? 0) > 0 else {
                throw failure("Native owner lost displayed picture", natural: true)
            }
            guard sample["timeControlStatus"] as? Int == AVPlayer.TimeControlStatus.playing.rawValue,
                  let rate = sample["rate"] as? Double, abs(rate - 1) <= 0.05 else {
                throw failure("Native owner stopped or waited during hold", natural: true)
            }
            return (uptime, media, sample["accessLogEventIndex"] as? Int, sample["stalls"] as? Int)
        }
        // Start after the picker and evidence capture. Only this owner's media
        // movement during this observation window counts towards the hold.
        let first = try sample()
        firstUptime = first.uptime
        var previous = first
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            let next = try sample()
            let seconds = next.uptime - previous.uptime, advanced = next.media - previous.media
            guard (0.5...8).contains(seconds) else { throw failure("Missing observation interval") }
            guard advanced >= seconds * 0.8 else { throw failure("Media fell behind owner clock", natural: true) }
            guard advanced <= seconds * 1.2 + 0.2 else { throw failure("Media jumped during hold", natural: true) }
            if let index = previous.logIndex, let stalls = previous.stalls, stalls >= 0 {
                guard let nextIndex = next.logIndex, let nextStalls = next.stalls else { throw failure("Lost access-log observation") }
                if nextIndex == index {
                    guard nextStalls == stalls else { throw failure("AV stall count changed", natural: true) }
                }
                else {
                    guard nextIndex == index + 1 else { throw failure("Access-log history changed without a sample") }
                    guard nextStalls == 0 else { throw failure("New AV log event reported a stall", natural: true) }
                }
            } else if let stalls = next.stalls, stalls > 0 { throw failure("Newly reported AV stall", natural: true) }
            previous = next
        } while previous.uptime - first.uptime < 90
        let elapsed = previous.uptime - first.uptime, advance = previous.media - first.media
        guard advance >= elapsed * 0.94 else { throw failure("Sustained media advancement insufficient", natural: true) }
        capture(evidence + " after hold")
        XCTAssertEqual(try selectedRoute(), route)
        attach(evidence + ": same native player/item/attempt for 90s; media advance=\(advance)s. Review both pictures for correct programme; no audible-output claim.")
    }

    func testFreshRetryProgressAndCancelAfterRealChannelFailure() throws {
        try openStation("Sky Sports Cricket")
        let retry = app.buttons["playback-error-retry"]
        guard retry.waitForExistence(timeout: 110) else {
            capture("Sky Cricket did not expose a failed-player Retry in this bounded window")
            throw XCTSkip("Current production did not exercise a terminal channel failure; offline ownership/freshness regressions remain separate")
        }
        capture("Actual channel failure before explicit Retry")
        retry.tap()
        let panel = app.descendants(matching: .any)["stream-resolution-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Explicit Retry gave no visible fresh-discovery progress")
        capture("Fresh Retry progress in retained failed pane")
        let cancel = app.buttons["Cancel"].firstMatch
        guard cancel.exists && cancel.isHittable else {
            throw XCTSkip("Retry completed before cancellation was actionable; cancel was not exercised on device")
        }
        cancel.tap()
        XCTAssertTrue(wait(8) { !panel.exists })
        XCTAssertTrue(retry.waitForExistence(timeout: 8), "Cancel did not retain the recoverable failed player")
        capture("Cancelled fresh lookup retains failed player and Retry")
        attach("Actual failed player → Retry progress → Cancel → same recoverable error surface. Source/cache refresh is corroborated by local regression and private quality records, not assumed from the spinner.")
    }

    private func openStation(_ title: String) throws {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", "Watch \(title)")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        for _ in 0..<5 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isEnabled && button.isHittable)
        button.tap()
        let panel = app.descendants(matching: .any)["stream-resolution-panel"].firstMatch
        XCTAssertTrue(wait(5) { panel.exists || self.app.buttons["viewing-sources"].exists || self.app.alerts.count > 0 },
                      "Watch produced no prompt pending/player/error feedback")
        capture("\(title) Watch acknowledgement")
    }

    private func measurement() -> [String: Any]? {
        let element = app.descendants(matching: .any)["native-playback-measurement"].firstMatch
        guard element.exists, let value = element.value as? String,
              let data = value.data(using: .utf8), data.count < 4096 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func waitForReady(timeout: TimeInterval, excludingAttempt: String? = nil,
                              sameOwner: [String: Any]? = nil, replacingOwner: [String: Any]? = nil) -> [String: Any]? {
        var last: [String: Any]?
        var ready: [String: Any]?
        _ = wait(timeout) {
            guard let sample = self.measurement(), sample["readyForDisplay"] as? Bool == true,
                  let attempt = sample["attemptToken"] as? String, attempt != excludingAttempt,
                  sample["timeControlStatus"] as? Int == AVPlayer.TimeControlStatus.playing.rawValue,
                  let rate = sample["rate"] as? Double, abs(rate - 1) <= 0.05,
                  let time = sample["currentTimeSeconds"] as? Double else { last = nil; return false }
            if let replacingOwner {
                guard let oldItem = replacingOwner["physicalItemToken"] as? String,
                      let item = sample["physicalItemToken"] as? String, item != oldItem else { last = nil; return false }
            }
            let keys = ["playerToken", "itemToken", "attemptToken"]
            if let sameOwner, !keys.allSatisfy({ key in
                guard let token = sameOwner[key] as? String else { return false }
                return sample[key] as? String == token
            }) { last = nil; return false }
            defer { last = sample }
            guard let last, let previous = last["currentTimeSeconds"] as? Double,
                  keys.allSatisfy({ key in
                      guard let token = sample[key] as? String else { return false }
                      return last[key] as? String == token
                  }),
                  time > previous + 0.2 else { return false }
            ready = sample
            return true
        }
        return ready
    }

    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return condition()
    }

    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "Bounded physical acceptance scope"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
