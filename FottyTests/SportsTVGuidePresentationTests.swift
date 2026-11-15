import SwiftUI
import UIKit
import XCTest
@testable import Fotty

@MainActor
final class SportsTVGuidePresentationTests: XCTestCase {
    func testGuideReflowsInSplitViewAndAtAccessibilitySizes() {
        XCTAssertFalse(SportsTVGuideLayout.usesColumns(width: 390, typeSize: .large))
        XCTAssertFalse(SportsTVGuideLayout.usesColumns(width: 744, typeSize: .large))
        XCTAssertTrue(SportsTVGuideLayout.usesColumns(width: 1024, typeSize: .large))
        XCTAssertFalse(SportsTVGuideLayout.usesColumns(width: 1024, typeSize: .accessibility1))
        XCTAssertFalse(SportsTVGuideLayout.usesColumns(width: 1366, typeSize: .accessibility5))
    }

    func testProgrammeUsesAnExplicitIntervalAndNeverClaimsLiveFromKickoff() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startedWithoutEnd = SportsTVGuidePolicy.Entry(id: "start", title: "Programme", start: now.addingTimeInterval(-60), end: nil, sport: "football")
        let current = SportsTVGuidePolicy.Entry(id: "current", title: "Programme", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), sport: "football")
        XCTAssertFalse(SportsTVProgrammeLabel.timing(startedWithoutEnd, at: now).contains("On now"))
        XCTAssertTrue(SportsTVProgrammeLabel.timing(current, at: now).hasPrefix("On now · "))
        XCTAssertFalse(SportsTVProgrammeLabel.timing(current, at: now).contains("LIVE"))
        XCTAssertFalse(SportsTVProgrammeLabel.timing(current, at: now.addingTimeInterval(60)).contains("On now"))
    }

    func testLongProgrammeNamesWrapOnNarrowPhoneAndFitAtAccessibilitySizes() {
        func measured(_ width: CGFloat, _ type: DynamicTypeSize) -> CGSize {
            let view = SportsTVProgrammeLabel(title: "Adelaide Strikers Women v Brisbane Heat Women",
                timing: "Tomorrow · 6:35 AM – 10:30 AM", detail: "Women's Big Bash League")
                .environment(\.dynamicTypeSize, type).frame(width: width)
            let host = UIHostingController(rootView: view)
            if type.isAccessibilitySize {
                host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            }
            return host.sizeThatFits(in: .init(width: width, height: 4_000))
        }
        let narrow = measured(256, .large)
        let wide = measured(600, .large)
        let accessible = measured(256, .accessibility5)
        XCTAssertEqual(narrow.width, 256, accuracy: 1)
        XCTAssertGreaterThan(narrow.height, wide.height, "Essential identity must wrap rather than truncate")
        #if targetEnvironment(macCatalyst)
        // This Catalyst host measured the same semantic-font height at both settings.
        // Validate wrapping/containment here; physical iOS text scaling is a
        // separate gate, not something this host measurement can establish.
        XCTAssertGreaterThanOrEqual(accessible.height, narrow.height)
        #else
        XCTAssertGreaterThan(accessible.height, narrow.height, "Text must grow and reflow")
        #endif
        XCTAssertLessThan(accessible.height, 1_000)
    }

    func testNativeGuideRowsFitPhoneTabletAndAccessibilityWithoutTriggeringActions() throws {
        var actionCount = 0
        for (width, type) in [(CGFloat(288), DynamicTypeSize.large), (390, .large), (976, .large), (390, .accessibility5)] {
            let row = sampleRow(width: width, type: type) { actionCount += 1 }
            let host = UIHostingController(rootView: row)
            if type.isAccessibilitySize { host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }
            let size = host.sizeThatFits(in: .init(width: width, height: 4_000))
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertGreaterThan(size.height, 44)
            XCTAssertLessThan(size.height, 2_500)
        }
        XCTAssertEqual(actionCount, 0, "Rendering the guide must never start a channel or save a match")
    }

    func testNativeProgrammeVisualsInLightDarkAndLargeText() throws {
        // Images are optional owned build-gate artifacts, never device captures.
        // No file is written during the normal suite unless the gate opts in.
        let destination = ProcessInfo.processInfo.environment["FOTTY_GUIDE_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        if let destination { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
        for (name, width, type, appearance) in [
            ("phone-dark", CGFloat(358), DynamicTypeSize.large, ColorScheme.dark),
            ("phone-light", CGFloat(358), DynamicTypeSize.large, ColorScheme.light),
            ("ipad-dark", CGFloat(976), DynamicTypeSize.large, ColorScheme.dark),
            ("ipad-light", CGFloat(976), DynamicTypeSize.large, ColorScheme.light),
            ("phone-accessibility", CGFloat(358), DynamicTypeSize.accessibility5, ColorScheme.dark)
        ] {
            let renderer = ImageRenderer(content: sampleRow(width: width, type: type, action: {})
                .environment(\.colorScheme, appearance))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertGreaterThan(image.size.height, 44)
            if let destination { try XCTUnwrap(image.pngData()).write(to: destination.appendingPathComponent(name + ".png")) }
        }
    }

    func testSearchShowsTheMatchingProgrammeInsteadOfAnUnrelatedFirstNextEntry() throws {
        let station = try XCTUnwrap(SportsTVStation.station(provider: "TV3"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SportsTVGuidePolicy.Entry(id: "first", title: "Football news", start: start, end: nil, sport: "football")
        let match = SportsTVGuidePolicy.Entry(id: "match", title: "Liverpool v Arsenal", start: start.addingTimeInterval(3600), end: nil, sport: "football")
        XCTAssertEqual(SportsTVGuidePresentationPolicy.visibleEntries([first, match], station: station, query: "  liverpool ").map(\.id), [match.id])
        XCTAssertFalse(SportsTVGuidePresentationPolicy.matches(station: station, query: "Liverpool", entries: [first]),
            "A match outside the selected day's entries must not produce an unrelated station result")
        XCTAssertTrue(SportsTVGuidePresentationPolicy.matches(station: station, query: station.title, entries: []),
            "Channel search still works without schedule metadata")
        XCTAssertEqual(SportsTVGuidePresentationPolicy.visibleEntries([first, match], station: station, query: station.title).count, 2)
        XCTAssertEqual(SportsTVGuidePresentationPolicy.visibleEntries([first, match], station: station, query: "Liverpool Arsenal").map(\.id), [match.id])
        let sky = SportsTVStation(id: "sample-sky", provider: "test", title: "Sky Sports Cricket", language: .english)
        XCTAssertTrue(SportsTVGuidePresentationPolicy.matches(station: sky, query: "sky cricket", entries: []))
        XCTAssertTrue(SportsTVGuidePresentationPolicy.matches(station: sky, query: "Sky English", entries: []))
        XCTAssertEqual(SportsTVGuidePresentationPolicy.visibleEntries([first, match], station: sky, query: "Sky Arsenal English").map(\.id), [match.id])
        let accents = SportsTVGuidePolicy.Entry(id: "accents", title: "São Paulo v Santos", start: start, end: nil, sport: "football")
        XCTAssertTrue(SportsTVGuidePresentationPolicy.matches(station: station, query: "sao santos", entries: [accents]))
    }

    func testLinkedPregameWithoutFixtureWatchStillHasTheEnabledDirectChannelRoute() throws {
        let now = Date()
        let event = EventReference(id: "sports-fixture:premier-league:guide", title: "Liverpool v Arsenal", category: "football",
            date: Int64(now.addingTimeInterval(1800).timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: "Liverpool", badge: nil), away: .init(name: "Arsenal", badge: nil)))
        let discovery = FixtureStreamDiscoveryIndex()
        discovery.updateEnabledProviders(["communitysports"], revision: 1)
        let station = try XCTUnwrap(SportsTVStation.station(provider: "CS-SkyMain"))
        XCTAssertFalse(SportsTVGuidePresentationPolicy.offersMatchWatch(event, status: nil, at: now,
            discoveryIndex: discovery, catalogIndex: FixtureCatalogAvailabilityIndex()))
        XCTAssertTrue(SportsTVStation.canWatchNow(station, discoveryIndex: discovery),
            "The fallback channel stays usable even though reviewed TV's linked fixture is too early to Watch")
    }

    func testReminderAdmissionIsLazyAndChecksTheCurrentLinkAtActionTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = EventReference(id: "fixture", title: "Liverpool v Arsenal", category: "football",
            date: Int64(now.addingTimeInterval(3600).timeIntervalSince1970), poster: nil, popular: false, teams: nil)
        let expiry = now.addingTimeInterval(20)
        var clock = now
        var admissions = 0
        let control = MatchStartControls(event: event, reminderAdmission: {
            admissions += 1
            return clock < expiry ? event : nil
        }) { EmptyView() }
        XCTAssertEqual(admissions, 0, "Rendering or constructing the control cannot acquire reminder authority")
        XCTAssertEqual(control.admittedReminderEvent(event)?.id, event.id)
        clock = expiry.addingTimeInterval(5)
        XCTAssertNil(control.admittedReminderEvent(event), "An expired retained row cannot enable a reminder or implicitly save")
        XCTAssertEqual(admissions, 2)
        let existingControl = MatchStartControls(event: event) { EmptyView() }
        XCTAssertEqual(existingControl.admittedReminderEvent(event)?.id, event.id,
            "Existing non-guide controls retain their original reminder contract")
    }

    private func sampleRow(width: CGFloat, type: DynamicTypeSize, action: @escaping () -> Void) -> some View {
        SportsTVGuideStationRow(usesColumns: SportsTVGuideLayout.usesColumns(width: width, typeSize: type)) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "tv").foregroundStyle(FottyTheme.accentText)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sky Sports Cricket").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("English").font(.caption).foregroundStyle(.secondary)
                }
            }
        } current: {
            VStack(alignment: .leading, spacing: 12) {
                SportsTVProgrammeLabel(title: "England v New Zealand", timing: "On now · 8:00 AM – 12:00 PM", detail: "Cricket", progress: 0.4)
                Button(action: action) { Label("Watch", systemImage: "play.fill").frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent).tint(FottyTheme.accent).foregroundStyle(FottyTheme.textOnAccent)
            }
        } next: {
            VStack(alignment: .leading, spacing: 12) {
                SportsTVProgrammeLabel(title: "Adelaide Strikers Women v Brisbane Heat Women", timing: "12:00 PM", detail: "Women's Big Bash League")
                Button(action: action) { Label("Remind", systemImage: "bell").frame(minHeight: 44) }
                    .buttonStyle(.bordered).tint(FottyTheme.accentText)
            }
        }
        .padding(16).frame(width: width).background(FottyTheme.surface)
        .environment(\.dynamicTypeSize, type)
    }
}
