import XCTest

/// Production-feed measurements on physical owner hardware. Cache is retained:
/// a fresh launch is not a cold-cache test. CPU/memory/hitches target Fotty, not
/// the test runner. Interaction and settling include XCTest automation overhead.
final class CatalogPerformanceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let retainedIterations = 3

    private enum CollectorPlan: String {
        case appTargetCore = "app_target_core_v2"
        case scrollSignpostOnly = "scroll_signpost_only_v1"

        var tags: [String] {
            self == .appTargetCore ? ["app_cpu", "app_memory", "app_hitch", "wall_clock"] : ["scroll_signpost"]
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Catalog measurements require physical iOS/iPadOS hardware.")
        #else
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil else {
            throw XCTSkip("These measurements do not run on simulators.")
        }
        app = XCUIApplication()
        app.launchEnvironment["FOTTY_PHYSICAL_LIVE_TEST"] = "1"
        app.launchArguments = ["-fotty.onboarding.hasDismissed", "YES", "-fotty.setup.dismissed.v1", "YES"]
        app.launch()
        XCTAssertTrue(tab("tab-home").waitForExistence(timeout: 15))
        tap(tab("tab-home"))
        #endif
    }

    override func tearDownWithError() throws { app?.terminate() }

    func testPhysicalProductionHomeScrollMetrics() throws {
        try measureScroll(tabID: "tab-home", rowPrefix: "home-watch-now", surface: "Home")
    }

    func testPhysicalProductionMatchdayScrollMetrics() throws {
        try measureScroll(tabID: "tab-arena", rowPrefix: "matchday-row-", surface: "Matchday")
    }

    /// Supplementary instrumentation, not a passing substitute for core app
    /// metrics. Missing signpost events must remain externally unqualified.
    func testPhysicalProductionHomeScrollSignpostMetrics() throws {
        try measureScroll(tabID: "tab-home", rowPrefix: "home-watch-now", surface: "Home", plan: .scrollSignpostOnly)
    }

    func testPhysicalProductionMatchdayScrollSignpostMetrics() throws {
        try measureScroll(tabID: "tab-arena", rowPrefix: "matchday-row-", surface: "Matchday", plan: .scrollSignpostOnly)
    }

    func testPhysicalProductionLatestSearchMetrics() throws {
        let search = app.buttons["home-search"]
        for _ in 0..<3 where !search.isHittable { contentScroll.swipeDown() }
        XCTAssertTrue(search.isHittable)
        tap(search)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        let recorder = CatalogMetricReceipts()
        let before = catalogContext(rowPrefix: "search-result-")
        var invocation = 0
        measure(metrics: metrics(plan: .appTargetCore), options: options()) {
            let ordinal = invocation
            invocation += 1
            let term = ordinal.isMultiple(of: 2) ? "football" : "zz"
            let field = self.app.searchFields.firstMatch
            // Refocus only when the keyboard is absent. A repeated tap on an
            // already-focused searchable field triggered a 60-second XCTest
            // animation-idle wait in the physical 131 run after clearing.
            // Keep ordinary public automation and exact committed-input checks.
            if !self.app.keyboards.firstMatch.exists { self.tap(field) }
            if let existing = field.value as? String, existing != field.placeholderValue, !existing.isEmpty {
                let clear = field.buttons["Clear text"]
                XCTAssertTrue(clear.waitForExistence(timeout: 3))
                self.tap(clear)
                if !self.app.keyboards.firstMatch.exists { self.tap(field) }
            }
            // One typing command avoids repeated automation idle barriers.
            // Exact committed text remains required: partial input cannot pass.
            self.app.typeText(term)
            XCTAssertTrue(self.waitUntil(timeout: 3) { field.value as? String == term },
                          "Search lost committed input; this iteration cannot qualify")
            XCTAssertTrue(self.waitUntil(timeout: 5) {
                field.value as? String == term
                    && !self.app.staticTexts["Searching…"].exists
                    && (self.app.staticTexts["No matching fixtures or channels"].exists
                        || self.app.descendants(matching: .any).matching(
                            NSPredicate(format: "identifier BEGINSWITH %@", "search-result-")
                        ).firstMatch.exists)
            }, "Search did not settle for the latest committed query")
            recorder.recordWorkload(invocation: ordinal, queryLength: term.count,
                                    appForeground: self.app.state == .runningForeground)
        }
        try assertAndAttach(recorder, invocationCount: invocation, before: before,
                            after: catalogContext(rowPrefix: "search-result-"), surface: "Search", scrolling: false,
                            plan: .appTargetCore)
    }

    private func measureScroll(tabID: String, rowPrefix: String, surface: String,
                               plan: CollectorPlan = .appTargetCore) throws {
        let selected = tab(tabID)
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        tap(selected)
        XCTAssertTrue(waitUntil(timeout: 5) { selected.isSelected && self.contentScroll.isHittable })
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", rowPrefix))
        guard rows.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("Insufficient production \(surface) workload: no catalog rows; preferences and cache are unchanged.")
        }
        let preflightScroll = contentScroll
        let preflightAnchors = movementAnchors(rows: rows, viewport: preflightScroll.frame)
        preflightScroll.swipeUp()
        let preflightMovement = observedMovement(for: preflightAnchors)
        preflightScroll.swipeDown()
        guard preflightMovement > 8 else {
            throw XCTSkip("Insufficient production \(surface) workload: no verified catalog translation after a swipe; an unmoving screen cannot qualify as scroll evidence. Preferences and cache are unchanged.")
        }
        let before = catalogContext(rowPrefix: rowPrefix)
        let recorder = CatalogMetricReceipts()
        var invocation = 0
        measure(metrics: metrics(plan: plan), options: options()) {
            let ordinal = invocation
            invocation += 1
            let scroll = self.contentScroll
            XCTAssertTrue(scroll.exists && scroll.isHittable)
            let anchors = self.movementAnchors(rows: rows, viewport: scroll.frame)
            scroll.swipeUp()
            // The automatic measured block includes anchor inspection,
            // observed translation and restoration. Check movement before
            // restoring, so a return to origin cannot disguise a stationary
            // workload. Do not claim this is isolated animation/frame timing.
            let movement = self.observedMovement(for: anchors)
            recorder.recordMovement(invocation: ordinal, translationPoints: movement)
            scroll.swipeDown()
            XCTAssertEqual(self.app.state, .runningForeground)
            recorder.recordWorkload(invocation: ordinal, queryLength: nil,
                                    appForeground: self.app.state == .runningForeground)
        }
        try assertAndAttach(recorder, invocationCount: invocation, before: before,
                            after: catalogContext(rowPrefix: rowPrefix), surface: surface, scrolling: true, plan: plan)
    }

    private func options() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = retainedIterations
        // Use XCTest's documented automatic begin/end lifecycle. Our physical
        // XCTest 27 gate rejected the manualStop lifecycle and produced no
        // metrics, despite the explicit calls. Keep the complete interaction
        // block measured, rather than mixing automatic and manual boundaries.
        return options
    }

    private func metrics(plan: CollectorPlan) -> [any XCTMetric] {
        // Pass concrete Apple collectors directly. A protocol forwarding
        // decorator prevented XCTest's built-in CPU collector setup on device
        // and failed with missing _data. Do not recreate private collector APIs.
        if plan == .scrollSignpostOnly {
            return [XCTOSSignpostMetric.scrollingAndDecelerationMetric]
        }
        // Conditional signpost availability on device caused a mixed collector
        // set to discard otherwise useful retained app samples in build 132.
        // Keep this new baseline's ten app scalars separate from the six
        // supplementary signpost values; never fill missing values with zeros.
        return [
            XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
            XCTHitchMetric(application: app), XCTClockMetric()
        ]
    }

    private func assertAndAttach(_ recorder: CatalogMetricReceipts, invocationCount: Int,
                                 before: [String: Any], after: [String: Any], surface: String,
                                 scrolling: Bool, plan: CollectorPlan) throws {
        var receipt: [String: Any] = [
            "surface": surface, "warmupInvocations": 1, "retainedIterations": retainedIterations,
            "totalInvocations": invocationCount, "cacheCleared": false,
            "normalProductionFeeds": true, "includesAutomationOverhead": true,
            "crossBuildComparisonQualified": false, "contextBefore": before, "contextAfter": after,
            "workloads": recorder.workloads(),
            "collectorPlan": plan.rawValue,
            "expectedMetricTags": plan.tags, "scrollMovement": recorder.movements(),
            "externalMetricValidationRequired": true,
            "metricValidation": "not_qualified_until_xcresult_values_are_verified",
            "requiredReturnedEvidence": plan == .appTargetCore
                ? "finite app CPU/memory/hitch/wall values for every retained iteration; actual movement for scroll journeys; supplementary scroll signposts are a separate unqualified gate"
                : "finite six scroll signpost values for every retained iteration; actual movement; not core app-target CPU/memory/hitch/wall qualification",
            "measurementBoundary": "automatic_interaction_block",
            "measuredScrollSwipesPerInvocation": scrolling ? 2 : 0,
            "scrollRestorationOutsideMeasurement": false,
            "includesAnchorInspection": scrolling,
            "includesSearchFocusAndClearing": !scrolling
        ]
        if let build = ProcessInfo.processInfo.environment["FOTTY_MEASURED_BUILD"],
           build.count <= 16, build.allSatisfy(\.isNumber) { receipt["build"] = build }
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        XCTAssertLessThan(data.count, 65_536, "Keep performance evidence bounded and scalar-only")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        let collectorLabel = plan == .appTargetCore ? "app-target" : "scroll-signpost"
        attachment.name = "Production \(surface) \(collectorLabel) metrics; warm-up and workload context labeled"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(invocationCount, retainedIterations + 1, "XCTest must execute one discarded warm-up plus three retained iterations")
        for ordinal in 1...retainedIterations {
            XCTAssertTrue(recorder.workloads().contains {
                $0["invocation"] as? Int == ordinal && $0["appForeground"] as? Bool == true
            }, "Retained invocation \(ordinal) did not complete its foreground workload")
            if scrolling {
                XCTAssertTrue(recorder.movements().contains {
                    $0["invocation"] as? Int == ordinal && ($0["translationPoints"] as? Double ?? 0) > 8
                }, "Retained invocation \(ordinal) did not move the catalog; swipe API execution alone is not scroll evidence")
            }
        }
    }

    private struct MovementAnchor {
        let element: XCUIElement
        let originalY: CGFloat
    }

    private func movementAnchors(rows: XCUIElementQuery, viewport: CGRect) -> [MovementAnchor] {
        // Resolve at most twelve visible catalog anchors. Their labels remain
        // transient query keys only; no names/identities enter the receipt.
        var anchors: [MovementAnchor] = []
        for row in rows.allElementsBoundByIndex.prefix(24) {
            let frame = row.frame
            guard frame.width > 0, frame.height > 0, frame.intersects(viewport), row.isHittable else { continue }
            let matching = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label == %@", row.identifier, row.label)).firstMatch
            // SwiftUI may expose a semantic wrapper and leaf with the same
            // label/identifier. Baseline the exact resolved query we compare.
            let resolvedFrame = matching.frame
            guard resolvedFrame.width > 0, resolvedFrame.height > 0, resolvedFrame.minY.isFinite else { continue }
            anchors.append(.init(element: matching, originalY: resolvedFrame.minY))
            if anchors.count == 12 { break }
        }
        return anchors
    }

    private func observedMovement(for anchors: [MovementAnchor]) -> Double {
        var translation = 0.0
        for anchor in anchors where anchor.element.exists {
            let frame = anchor.element.frame
            guard frame.width > 0, frame.height > 0, frame.minY.isFinite else { continue }
            translation = max(translation, Double(abs(frame.minY - anchor.originalY)))
        }
        // Lazy eviction or changed row labels alone are not proof of movement.
        return translation
    }

    private func catalogContext(rowPrefix: String) -> [String: Any] {
        // Counts/thermal state only. No fixture names, URLs, full AX tree, user
        // preferences or provider tokens are sampled or uploaded.
        ["accessibleRows": app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", rowPrefix)).count,
         "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
         "uptimeSeconds": ProcessInfo.processInfo.systemUptime,
         "osMajor": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
         "osMinor": ProcessInfo.processInfo.operatingSystemVersion.minorVersion]
    }

    private func tab(_ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).allElementsBoundByIndex.last(where: { $0.isHittable })
            ?? app.buttons.matching(identifier: identifier).element(boundBy: 0)
    }

    private var contentScroll: XCUIElement {
        app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            ?? app.scrollViews.firstMatch
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.exists && element.isHittable)
        element.tap()
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}

private final class CatalogMetricReceipts {
    private let lock = NSLock()
    private var workloadRows: [[String: Any]] = []
    private var movementRows: [[String: Any]] = []

    func recordMovement(invocation: Int, translationPoints: Double) {
        lock.lock(); defer { lock.unlock() }
        guard movementRows.count < 8 else { return }
        movementRows.append(["invocation": invocation, "translationPoints": translationPoints])
    }

    func recordWorkload(invocation: Int, queryLength: Int?, appForeground: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard workloadRows.count < 8 else { return }
        var row: [String: Any] = ["invocation": invocation, "warmup": invocation == 0, "appForeground": appForeground]
        if let queryLength { row["queryLength"] = queryLength }
        workloadRows.append(row)
    }

    func workloads() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return workloadRows }
    func movements() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return movementRows }
}
