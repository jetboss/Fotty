import Foundation
import UIKit
import XCTest

/// Public, production-data checks on the explicitly selected physical iPad.
/// No fixture/storage injection, reminder actions, private SpringBoard APIs,
/// animation-idle overrides, or FPL changes. Run phases separately.
final class SportsWidgetPhysicalUITests: XCTestCase {
    private var app: XCUIApplication!
    private var springboard: XCUIApplication!
    private var deadline = Date.distantPast
    private let title = "Your sports plan"

    private struct Review: Codable, Equatable {
        let query: String
        let home: String
        let away: String
        let kickoff: TimeInterval
        let timeText: String
        let searchStatus: String
        let homePage: Int
        let windowWidth: Double
        let windowHeight: Double
        let blank: Rect
    }
    private struct Rect: Codable, Equatable {
        let x: Double, y: Double, width: Double, height: Double
        init(_ frame: CGRect) {
            x = frame.minX; y = frame.minY; width = frame.width; height = frame.height
        }
        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Position { let page: Int, count: Int }
    private struct HomeGeometry {
        let window: CGRect
        let visibleIcons: [CGRect]
        var grid: [Rect] {
            visibleIcons.filter { $0.minY > window.minY + 60 && $0.maxY < window.maxY - 100 }
                .map(Rect.init).sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        }
    }
    private struct Receipt: Codable {
        let version: Int
        let token: String
        let review: Review
        let resultID: String
        var bookmarkCreationAttempted: Bool
        var bookmarkConfirmed: Bool
        var originalPage: Int?
        var originalCount: Int?
        var originalIcons: [Rect]
        var ownedPage: Int?
        var additionAttempted: Bool
        var widgetConfirmed: Bool
        var widgetFrame: Rect?
        var populatedConfirmedAt: Date?
        let startedAt: Date
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        deadline = Date().addingTimeInterval(210)
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Widget physical gate requires Jet iPad; no Catalyst or simulator.")
        #else
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil,
              UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Widget physical gate requires the selected physical iPad.")
        }
        app = XCUIApplication()
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        #endif
    }

    /// First run without fixture or blank-rectangle arguments. Review this
    /// screenshot before supplying a current, genuinely blank Home rectangle.
    func testPhysicalSportsWidgetInspectHome() throws {
        try home()
        attachHomeGeometry(stage: "Inspect current Home before any mutation")
    }

    /// Required environment (reviewed real data, not an injected fixture):
    /// FOTTY_WIDGET_GATE_TOKEN; FOTTY_WIDGET_QUERY; FOTTY_WIDGET_HOME;
    /// FOTTY_WIDGET_AWAY; FOTTY_WIDGET_KICKOFF (Unix seconds, >30min away);
    /// FOTTY_WIDGET_TIME_TEXT; FOTTY_WIDGET_SEARCH_STATUS_TEXT;
    /// FOTTY_WIDGET_HOME_WIDTH/HEIGHT/PAGE; FOTTY_WIDGET_HOME_BLANK_RECT=x,y,w,h.
    /// Optional FOTTY_WIDGET_KEEP_FOR_EXPIRY=1 retains only owned artifacts.
    /// Optional FOTTY_WIDGET_GALLERY_FAMILY_TEXT is the exact, reviewed native
    /// medium/large size caption when the gallery lacks a size button.
    func testPhysicalSportsWidgetInstallPopulateAndTap() throws {
        let review = try reviewedInput()
        let token = try gateToken()
        guard Date(timeIntervalSince1970: review.kickoff).timeIntervalSinceNow > 1800 else {
            throw unavailable("Review", "The reviewed real fixture is no longer more than 30 minutes away.")
        }
        let prior = try readReceiptIfPresent()
        if let prior {
            guard prior.review == review, prior.token == token, !prior.additionAttempted else {
                throw unavailable("Ownership", "An existing gate receipt requires its separate cleanup; no duplicate widget will be added.")
            }
        }
        launchProductionApp()
        let result = try openReviewedDetails(review, expectedResultID: prior?.resultID, permitsUpcomingTap: true)
        let save = app.buttons["match-details-save"].firstMatch
        try require(save.waitForExistence(timeout: 5), stage: "Details", "Save control is unavailable.")
        let initiallySaved = save.label.contains("Remove from My Matchday")
        var receipt = prior ?? Receipt(version: 1, token: token, review: review, resultID: result.identifier,
            bookmarkCreationAttempted: false, bookmarkConfirmed: false, originalPage: nil,
            originalCount: nil, originalIcons: [], ownedPage: nil, additionAttempted: false,
            widgetConfirmed: false, widgetFrame: nil, populatedConfirmedAt: nil, startedAt: Date())
        if !initiallySaved {
            try require(save.label.contains("Save to My Matchday"), stage: "Save", "Unrecognized save action; nothing was toggled.")
            receipt.bookmarkCreationAttempted = true
            try persist(receipt, stage: "Before the one owned bookmark save")
            try tap(save, stage: "Save without a reminder")
            try require(wait(5) { save.label.contains("Remove from My Matchday") }, stage: "Save", "The new save was not acknowledged.")
            receipt.bookmarkConfirmed = true
        } else if prior?.bookmarkCreationAttempted == true {
            receipt.bookmarkConfirmed = true
        }
        try require(!app.alerts.firstMatch.exists, stage: "Save", "Saving alone presented an alert; no notification permission was granted.")
        try persist(receipt, stage: "Bookmark state confirmed; no bell was tapped")
        try tap(app.buttons["Close"].firstMatch, stage: "Close match details")
        if app.buttons["Done"].firstMatch.exists { try tap(app.buttons["Done"].firstMatch, stage: "Close Search") }
        try home()
        try require(!sportsHeaderExists(), stage: "Home ownership", "An existing visible sports-plan widget is not owned by this test.")
        let original = try position()
        receipt.originalPage = original.page; receipt.originalCount = original.count
        let geometry = homeGeometry()
        receipt.originalIcons = geometry.grid
        try persist(receipt, stage: "Home layout before installation")
        attachHomeGeometry(stage: "Home layout before installing exactly one widget", geometry: geometry)
        try beginHomeEditing(review, geometry: geometry)
        try createTrailingEmptyPage(after: original.count)
        receipt.ownedPage = original.count + 1
        try persist(receipt, stage: "New trailing empty edit page; existing pages untouched")
        try tap(try visibleControl(["Edit"], in: springboard), stage: "Native Home Edit menu")
        try tap(try visibleControl(["Add Widget", "Add Widgets"], in: springboard), stage: "Open native widget gallery")
        try chooseSportsMediumOrLargePreview(review)
        receipt.additionAttempted = true
        try persist(receipt, stage: "Before native Add Widget on the verified sports family")
        try tap(try visibleControl(["Add Widget", "Add Widgets"], in: springboard), stage: "Add only Your sports plan")
        if let done = optionalVisibleControl(["Done"], in: springboard) { try tap(done, stage: "Finish Home editing") }
        try require(try position().page == receipt.ownedPage, stage: "Owned page", "The system did not place the widget on the new empty page.")
        let widget = try ownedWidget(receipt, requiresTeams: true)
        let row = widget.links.allElementsBoundByIndex.first { $0.isHittable && includes($0, review.home) && includes($0, review.away) }
            ?? widget.buttons.allElementsBoundByIndex.first { $0.isHittable && includes($0, review.home) && includes($0, review.away) }
            ?? widget.staticTexts.allElementsBoundByIndex.first { visible($0) && includes($0, review.home) && includes($0, review.away) }
        guard let row else { throw unavailable("Actual row tap", "The installed widget did not expose an identifiable real row; a system URI was not substituted.") }
        try require(includes(row, review.timeText), stage: "Populated widget", "This reviewed match row does not show its exact scheduled time; another row cannot supply the receipt.")
        try require(!hasLiveStatus(row), stage: "Populated widget", "This reviewed future match row is incorrectly presented as Live.")
        receipt.widgetConfirmed = true; receipt.widgetFrame = Rect(widget.frame)
        receipt.populatedConfirmedAt = Date()
        try persist(receipt, stage: "Installed populated sports widget row confirmed")
        capture(stage: "Installed real populated sports widget")
        if row.isHittable { try tap(row, stage: "Tap installed widget's exact reviewed row") }
        else {
            // A normal touch at the visible row, inside this verified widget.
            try require(widget.frame.contains(row.frame), stage: "Actual row tap", "The row is outside the owned widget.")
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        try require(app.wait(for: .runningForeground, timeout: 8), stage: "Widget destination", "Fotty did not open from the actual row.")
        let target = app.descendants(matching: .any)["matchday-reminder-target"].firstMatch
        try require(wait(8) { target.exists && includes(target, review.home) && includes(target, review.away) },
                    stage: "Widget destination", "Matchday did not reveal the exact reviewed saved fixture.")
        try require(!app.descendants(matching: .any)["viewing-experience"].firstMatch.exists,
                    stage: "Widget destination", "The saved-match widget unexpectedly opened playback.")
        try require(!app.staticTexts["Your match reminder"].firstMatch.exists,
                    stage: "Widget destination", "A save-only widget tap falsely described its context as a notification reminder.")
        capture(stage: "Actual populated-widget row opens exact Matchday context without playback")
        if environment["FOTTY_WIDGET_KEEP_FOR_EXPIRY"] == "1" {
            try persist(receipt, stage: "Retained only owned widget/bookmark for real expiry; separate cleanup required")
            try home()
            try goToPage(try XCTUnwrap(receipt.ownedPage))
        } else { try cleanup(&receipt) }
    }

    /// Does not open Fotty first: doing so could legitimately renew the shared
    /// snapshot. Supply its independently read actual createdAt as Unix seconds.
    func testPhysicalSportsWidgetInspectExpiry() throws {
        let receipt = try requireReceipt()
        guard receipt.widgetConfirmed, receipt.widgetFrame != nil, receipt.ownedPage != nil,
              let confirmedAt = receipt.populatedConfirmedAt else {
            throw unavailable("Expiry ownership", "No confirmed populated-widget row receipt; a missing-data fallback cannot qualify expiry.")
        }
        guard let value = environment["FOTTY_WIDGET_SNAPSHOT_CREATED_AT"], let epoch = Double(value), epoch.isFinite else {
            throw unavailable("Expiry receipt", "Supply the real shared snapshot createdAt; save/add time is not a substitute.")
        }
        try require(epoch >= receipt.startedAt.timeIntervalSince1970 - 5
                    && epoch <= confirmedAt.timeIntervalSince1970 + 5,
                    stage: "Expiry receipt", "The independently read snapshot timestamp is outside this confirmed installation; an old snapshot cannot supply the expiry clock.")
        let age = Date().timeIntervalSince1970 - epoch
        try require(age >= 1801, stage: "Expiry timing", "The actual 30-minute snapshot lifetime has not elapsed; the clock was not changed.")
        try home()
        try goToPage(try XCTUnwrap(receipt.ownedPage))
        let widget = try ownedWidget(receipt, requiresTeams: false)
        let expired = wait(10) { includes(widget, "Open Fotty for your plan") && !includes(widget, receipt.review.home) && !includes(widget, receipt.review.away) }
        capture(stage: "Actual installed widget after snapshot age \(Int(age)) seconds")
        attach("Expiry observed=\(expired); actual snapshot age=\(age)s. WidgetKit may apply entries late; a missing transition is unqualified physical expiry, not by itself a source-code diagnosis.", name: "Widget expiry receipt")
        try require(expired, stage: "Physical expiry", "The installed widget's stale fallback was not observed within the bounded gate.")
    }

    /// Works after an interrupted install as well as after the held expiry.
    /// Missing/ambiguous ownership is a stop, never permission to remove a widget.
    func testPhysicalSportsWidgetCleanupOwnedArtifacts() throws {
        var receipt = try requireReceipt()
        try cleanup(&receipt)
    }

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private func gateToken() throws -> String {
        guard let token = environment["FOTTY_WIDGET_GATE_TOKEN"],
              token.range(of: #"^[A-Za-z0-9_-]{8,64}$"#, options: .regularExpression) != nil else {
            throw unavailable("Ownership token", "Supply a new bounded gate token; existing test receipts are never overwritten blindly.")
        }
        return token
    }
    private func reviewedInput() throws -> Review {
        func text(_ key: String) throws -> String {
            guard let value = environment[key], !value.isEmpty, value.count <= 160, !value.contains("://") else {
                throw unavailable("Review", "Missing or invalid reviewed \(key).")
            }
            return value
        }
        guard let kickoff = Double(try text("FOTTY_WIDGET_KICKOFF")), kickoff.isFinite,
              let width = Double(try text("FOTTY_WIDGET_HOME_WIDTH")), width.isFinite,
              let height = Double(try text("FOTTY_WIDGET_HOME_HEIGHT")), height.isFinite,
              let homePage = Int(try text("FOTTY_WIDGET_HOME_PAGE")), (1...8).contains(homePage) else {
            throw unavailable("Review geometry", "Invalid reviewed time/window numbers.")
        }
        let numbers = try text("FOTTY_WIDGET_HOME_BLANK_RECT").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] >= 12, numbers[3] >= 12 else {
            throw unavailable("Review geometry", "Supply a genuinely blank current Home rectangle x,y,width,height.")
        }
        return try Review(query: text("FOTTY_WIDGET_QUERY"), home: text("FOTTY_WIDGET_HOME"), away: text("FOTTY_WIDGET_AWAY"),
            kickoff: kickoff, timeText: text("FOTTY_WIDGET_TIME_TEXT"), searchStatus: text("FOTTY_WIDGET_SEARCH_STATUS_TEXT"),
            homePage: homePage, windowWidth: width, windowHeight: height, blank: Rect(CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])))
    }
    private func receiptURL() throws -> URL {
        let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("FottySportsWidgetPhysical", isDirectory: true)
        return directory.appendingPathComponent(try gateToken()).appendingPathExtension("json")
    }
    private func readReceiptIfPresent() throws -> Receipt? {
        let url = try receiptURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 32_768 else { throw unavailable("Ownership", "Owned receipt is oversized.") }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        try require(receipt.version == 1 && receipt.token == gateToken(), stage: "Ownership", "Receipt does not belong to this gate.")
        return receipt
    }
    private func requireReceipt() throws -> Receipt {
        guard let receipt = try readReceiptIfPresent() else { throw unavailable("Ownership", "No owned install receipt; preexisting widgets/saves will not be removed.") }
        return receipt
    }
    private func persist(_ receipt: Receipt, stage: String) throws {
        let url = try receiptURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: url, options: .atomic)
        attach(String(decoding: data, as: UTF8.self), name: "Owned widget receipt: \(stage)")
    }

    private func launchProductionApp() {
        // This flag allows real catalog/continuity work in the existing app;
        // unlike deterministic UI flags it supplies no fixture or user data.
        app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        app.launch()
    }
    private func openReviewedDetails(_ review: Review, expectedResultID: String?, permitsUpcomingTap: Bool) throws -> XCUIElement {
        let homeTab = app.buttons.matching(identifier: "tab-home").allElementsBoundByIndex.first { $0.isHittable }
        if let homeTab { try tap(homeTab, stage: "Home for reviewed Search") }
        try tap(app.buttons["home-search"].firstMatch, stage: "Open production Search")
        let search = app.descendants(matching: .any)["global-sports-search"].firstMatch
        try require(search.waitForExistence(timeout: 5), stage: "Search", "Production Search did not open.")
        let field = search.searchFields.firstMatch
        try tap(field, stage: "Focus production Search")
        let prior = field.value as? String ?? ""
        if !prior.isEmpty && prior != field.placeholderValue {
            try tap(field.buttons["Clear text"].firstMatch, stage: "Native Clear text")
            try require(wait(3) { (field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue }, stage: "Search", "Native Clear did not clear the complete query.")
        }
        try tap(field, stage: "Reacquire Search focus")
        field.typeText(review.query)
        try require(wait(5) { field.value as? String == review.query }, stage: "Search", "The complete reviewed query was not committed; no suffix repair.")
        let candidates = search.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-result-"))
        try require(wait(8) { candidates.count > 0 && !app.staticTexts["Searching…"].exists }, stage: "Search", "Real results did not settle.")
        let matching = candidates.allElementsBoundByIndex.prefix(20).filter { includes($0, review.home) && includes($0, review.away) }
        let ids = Set(matching.map(\.identifier))
        try require(ids.count == 1, stage: "Fixture identity", "Reviewed team names do not uniquely identify one current result.")
        let result = try XCTUnwrap(matching.first)
        if let expectedResultID { try require(result.identifier == expectedResultID, stage: "Fixture identity", "The current result ID differs from the owned save; no identity was guessed.") }
        if permitsUpcomingTap {
            try require(includes(result, review.searchStatus), stage: "Fixture status", "The real result does not match its reviewed upcoming status.")
            let explicitDetails = result.buttons["Details"].firstMatch
            if explicitDetails.exists { try tap(explicitDetails, stage: "Exact result Details") }
            else {
                let button = result.elementType == .button ? result : result.buttons.allElementsBoundByIndex.first { $0.isHittable && includes($0, review.home) && includes($0, review.away) }
                guard let button else { throw unavailable("Details", "No actual upcoming Details interaction was exposed; Watch was not substituted.") }
                try require(!includes(button, "Watch") && !hasLiveStatus(button), stage: "Details", "This result exposes playback, not the reviewed future Details route.")
                try tap(button, stage: "Reviewed future result opens Details")
            }
        }
        return result
    }

    private func home() throws {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        #endif
        try require(springboard.wait(for: .runningForeground, timeout: 6), stage: "Home", "SpringBoard did not become foreground.")
    }
    private func position() throws -> Position {
        let indicator = springboard.pageIndicators.firstMatch
        guard indicator.exists else { throw unavailable("Home pages", "The public Home page indicator is unavailable; no page position was guessed.") }
        for value in [indicator.value as? String ?? "", indicator.label] {
            let regex = try NSRegularExpression(pattern: #"(?i)(?:page\s*)?(\d+)\s*(?:of|/)\s*(\d+)"#)
            let string = value as NSString
            if let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: string.length)),
               let page = Int(string.substring(with: match.range(at: 1))), let count = Int(string.substring(with: match.range(at: 2))),
               page > 0, count > 0, count <= 8, page <= count { return Position(page: page, count: count) }
        }
        throw unavailable("Home pages", "The native page indicator does not expose a reviewed numeric page/count.")
    }
    private func beginHomeEditing(_ review: Review, geometry: HomeGeometry) throws {
        let frame = geometry.window
        try require(abs(frame.width - review.windowWidth) < 2 && abs(frame.height - review.windowHeight) < 2,
                    stage: "Blank Home context", "Window differs from the reviewed current Home screenshot.")
        try require(try position().page == review.homePage, stage: "Blank Home context",
                    "Home page differs from the reviewed screenshot; no background press was attempted.")
        let blank = review.blank.frame
        try require(frame.contains(blank) && blank.minY > frame.minY + 60 && blank.maxY < frame.maxY - 90,
                    stage: "Blank Home context", "Reviewed blank rectangle reaches system chrome/Dock/outside Home.")
        try require(!geometry.visibleIcons.contains { $0.intersects(blank) },
                    stage: "Blank Home context", "An icon occupies the reviewed background rectangle; nothing was long-pressed.")
        let point = springboard.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: blank.midX - frame.minX, dy: blank.midY - frame.minY))
        point.press(forDuration: 1.1)
        _ = try visibleControl(["Edit"], in: springboard)
    }
    private func createTrailingEmptyPage(after originalCount: Int) throws {
        for _ in 0..<8 {
            try checkBudget("New empty Home page")
            let current = try position()
            if current.page == originalCount + 1 {
                try require(gridIconFrames().isEmpty && !sportsHeaderExists(), stage: "New empty Home page", "The new trailing edit page is not empty; existing items were not moved.")
                capture(stage: "New empty trailing edit page before Add Widget")
                return
            }
            try require(current.page <= originalCount, stage: "New empty Home page", "Unexpected native page index; no existing page was rearranged.")
            springboard.swipeLeft()
        }
        throw unavailable("New empty Home page", "The public editor could not expose a new trailing empty page; existing pages remain untouched.")
    }
    private func goToPage(_ page: Int) throws {
        for _ in 0..<8 {
            try checkBudget("Owned Home page")
            let current = try position()
            if current.page == page { return }
            try require(page <= current.count, stage: "Owned Home page", "The receipt's owned page no longer exists.")
            if current.page < page { springboard.swipeLeft() } else { springboard.swipeRight() }
        }
        throw unavailable("Owned Home page", "The public Home navigation did not reach the owned page.")
    }
    private func chooseSportsMediumOrLargePreview(_ review: Review) throws {
        let search = springboard.searchFields.firstMatch
        try tap(search, stage: "Native widget gallery Search")
        search.typeText("Fotty")
        try require(wait(3) { search.value as? String == "Fotty" }, stage: "Gallery Search", "The native gallery query was not committed.")
        var chose = false
        for name in ["Fotty Sports Hub", "FottySportsHub", "Fotty"] {
            let cell = springboard.cells.containing(.staticText, identifier: name).firstMatch
            if cell.exists && cell.isHittable { try tap(cell, stage: "Verified Fotty gallery entry"); chose = true; break }
            let label = springboard.staticTexts[name].firstMatch
            let window = springboard.windows.firstMatch.frame
            if visible(label), label.frame.maxX < window.midX, search.value as? String == "Fotty" {
                label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                chose = true; break
            }
        }
        try require(chose, stage: "Gallery app entry", "No verified visible Fotty sidebar entry; no unrelated app was selected.")
        for _ in 0..<6 {
            try checkBudget("Sports medium/large preview")
            _ = try visibleControl(["Add Widget", "Add Widgets"], in: springboard)
            if sportsHeaderExists() {
                if let size = optionalVisibleControl(["Medium", "Large", "Medium Widget", "Large Widget"], in: springboard) {
                    try tap(size, stage: "Native medium/large family choice")
                    try require(sportsHeaderExists(), stage: "Sports family", "The size action no longer shows Your sports plan.")
                    return
                }
                if let sizeText = environment["FOTTY_WIDGET_GALLERY_FAMILY_TEXT"], !sizeText.isEmpty,
                   ["medium", "large"].contains(where: { sizeText.localizedCaseInsensitiveContains($0) }),
                   visible(springboard.staticTexts[sizeText].firstMatch) { return }
            }
            springboard.swipeLeft()
        }
        capture(stage: "Sports medium/large preview unavailable; no widget was added")
        throw unavailable("Sports medium/large preview", "No public size control or reviewed visible family caption qualified medium/large; no FPL widget was added.")
    }

    private func cleanup(_ receipt: inout Receipt) throws {
        if receipt.additionAttempted {
            try home(); try goToPage(try XCTUnwrap(receipt.ownedPage))
            let widget = try ownedWidget(receipt, requiresTeams: false)
            capture(stage: "Only gate-owned widget before removal")
            try require(widget.isHittable, stage: "Widget cleanup", "The uniquely owned widget cannot be normally pressed.")
            widget.press(forDuration: 1.1)
            try tap(try visibleControl(["Remove Widget"], in: springboard), stage: "Remove only owned sports widget")
            _ = wait(5) { optionalVisibleControl(["Remove"], in: springboard) != nil || !widget.exists }
            if let remove = optionalVisibleControl(["Remove"], in: springboard) { try tap(remove, stage: "Confirm only widget removal") }
            if let done = optionalVisibleControl(["Done"], in: springboard) { try tap(done, stage: "Finish owned widget removal") }
            try require(wait(8) { !widget.exists && !sportsHeaderExists()
                && (try? position().count) == receipt.originalCount },
                stage: "Widget cleanup", "Owned widget removal/page restoration is not acknowledged; keep the ownership receipt for retry.")
            receipt.additionAttempted = false; receipt.widgetConfirmed = false
            receipt.populatedConfirmedAt = nil
            try persist(receipt, stage: "Owned widget removed; existing widgets untouched")
        }
        if receipt.bookmarkCreationAttempted {
            launchProductionApp()
            let result = try openReviewedDetails(receipt.review, expectedResultID: receipt.resultID, permitsUpcomingTap: false)
            try require(result.exists && result.isHittable, stage: "Bookmark cleanup", "The exact owned result is not available for its secondary menu.")
            result.press(forDuration: 1.1)
            let remove = app.buttons["Remove from My Matchday"].firstMatch
            try require(remove.waitForExistence(timeout: 4) && remove.isHittable, stage: "Bookmark cleanup", "The exact new save does not expose Remove; no existing save was toggled.")
            try tap(remove, stage: "Remove only bookmark created by this gate")
            result.press(forDuration: 1.1)
            try require(app.buttons["Save to My Matchday"].firstMatch.waitForExistence(timeout: 4), stage: "Bookmark cleanup", "Removal of the owned save was not confirmed.")
            receipt.bookmarkCreationAttempted = false; receipt.bookmarkConfirmed = false
            try persist(receipt, stage: "Owned bookmark removed; no reminder bell was ever tapped")
        }
        try home()
        if let originalPage = receipt.originalPage { try goToPage(originalPage) }
        if let originalCount = receipt.originalCount {
            try require(try position().count == originalCount, stage: "Layout cleanup", "The temporary empty page did not disappear; Home layout restoration is unqualified.")
            try require(gridIconFrames() == receipt.originalIcons, stage: "Layout cleanup", "Existing Home-grid icon positions changed; no manual rearrangement was attempted.")
        }
        attachHomeGeometry(stage: "Home after removing only owned artifacts")
        try FileManager.default.removeItem(at: receiptURL())
    }
    private func ownedWidget(_ receipt: Receipt, requiresTeams: Bool) throws -> XCUIElement {
        let window = springboard.windows.firstMatch.frame
        let byChild = springboard.otherElements.containing(.staticText, identifier: title).allElementsBoundByIndex
        let byLabel = springboard.otherElements.matching(NSPredicate(format: "label CONTAINS %@", title)).allElementsBoundByIndex
        let candidates = (Array(byChild.prefix(16)) + Array(byLabel.prefix(16))).filter { element in
            let frame = element.frame
            return visible(element) && frame.width >= 160 && frame.height >= 80
                && frame.width < window.width * 0.75 && frame.height < window.height * 0.75
                && (!requiresTeams || (includes(element, receipt.review.home) && includes(element, receipt.review.away)))
                && !element.buttons["Add Widget"].firstMatch.exists
        }.sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let smallest = candidates.first else { throw unavailable("Owned widget", "No identifiable installed sports-plan widget; a gallery preview is not installed-widget evidence.") }
        let distinct = candidates.filter { !$0.frame.intersects(smallest.frame) }
        try require(distinct.isEmpty, stage: "Owned widget", "Multiple sports-plan widgets are visible; ownership is ambiguous.")
        if let recorded = receipt.widgetFrame {
            try require(abs(recorded.frame.midX - smallest.frame.midX) < 40 && abs(recorded.frame.midY - smallest.frame.midY) < 40,
                        stage: "Owned widget", "Widget moved from its recorded location; no preexisting widget will be removed.")
        }
        return smallest
    }
    private func sportsHeaderExists() -> Bool {
        springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).allElementsBoundByIndex.prefix(12).contains { visible($0) }
            || springboard.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", title)).allElementsBoundByIndex.prefix(12).contains { visible($0) }
    }
    private func homeGeometry() -> HomeGeometry {
        let window = springboard.windows.firstMatch.frame
        let frames = springboard.icons.allElementsBoundByIndex.prefix(120).map(\.frame)
            .filter { !$0.isEmpty && !$0.isNull && window.intersects($0) }
        return HomeGeometry(window: window, visibleIcons: frames)
    }
    private func gridIconFrames() -> [Rect] { homeGeometry().grid }
    private func attachHomeGeometry(stage: String, geometry: HomeGeometry? = nil) {
        capture(stage: stage)
        let snapshot = geometry ?? homeGeometry()
        let window = snapshot.window
        let indicator = springboard.pageIndicators.firstMatch
        let page = indicator.exists ? String(describing: indicator.value) : "unavailable"
        let geometryText = snapshot.grid.map { "x=\($0.x), y=\($0.y), w=\($0.width), h=\($0.height)" }.joined(separator: "\n")
        attach("Window=\(window); page=\(page); visible sports header=\(sportsHeaderExists())\nGrid icon GEOMETRY ONLY (no icon labels or Notes/other-widget text):\n\(geometryText)", name: stage)
    }
    private func includes(_ element: XCUIElement, _ text: String) -> Bool {
        element.exists && (element.label.localizedCaseInsensitiveContains(text)
            || element.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch.exists)
    }
    private func hasLiveStatus(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        // Liverpool/Livingston are names, not an independently exposed Live
        // status. Never turn a partial-word match into fixture-state evidence.
        return element.label.range(of: #"\bLive\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || element.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Live")).firstMatch.exists
    }
    private func visible(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && !frame.isNull && springboard.frame.intersects(frame)
    }
    private func optionalVisibleControl(_ labels: [String], in surface: XCUIElement) -> XCUIElement? {
        for label in labels {
            let button = surface.buttons[label].firstMatch
            if button.exists && button.isHittable { return button }
        }
        return nil
    }
    private func visibleControl(_ labels: [String], in surface: XCUIElement) throws -> XCUIElement {
        var control: XCUIElement?
        _ = wait(4) { control = optionalVisibleControl(labels, in: surface); return control != nil }
        guard let control else { throw unavailable("Native control", "No visible/hittable \(labels.joined(separator: "/")); no forced/private action.") }
        return control
    }
    private func tap(_ element: XCUIElement, stage: String) throws {
        try checkBudget(stage)
        try require(element.exists && element.isHittable, stage: stage, "The native control is not hittable.")
        try require(!element.identifier.contains("reminder-") && !["Remind me", "Add start reminder", "Enable alerts"].contains(element.label),
                    stage: stage, "This gate never taps a reminder/permission control.")
        element.tap()
    }
    private func wait(_ seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
        let end = min(Date().addingTimeInterval(seconds), deadline)
        while Date() < end {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }
    private func checkBudget(_ stage: String) throws {
        if Date() >= deadline { throw unavailable(stage, "The bounded phase budget ended; no timeout was enlarged.") }
    }
    private func require(_ value: @autoclosure () throws -> Bool, stage: String, _ message: String) throws {
        guard try value() else {
            XCTFail("[\(stage)] \(message)")
            throw NSError(domain: "Fotty.SportsWidgetPhysical", code: 1, userInfo: [NSLocalizedDescriptionKey: "[\(stage)] \(message)"])
        }
    }
    private func unavailable(_ stage: String, _ message: String) -> XCTSkip {
        attach("[\(stage)] \(message)\nNo force/private/quiescence override; ownership receipt retained if mutations began.", name: "Widget gate unavailable: \(stage)")
        return XCTSkip("[\(stage)] \(message)")
    }
    private func capture(stage: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = stage; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: String(text.prefix(20_000)))
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
