import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import Fotty

/// Actual production roots in a bounded native host, not a reconstruction of
/// their headings/cards. Still not physical iPhone/iPad or interaction evidence.
@MainActor
final class Fotty25DesignRenderTests: XCTestCase {
    private enum CaptureFailure: Error { case fixtureCatalogMissing }
    private struct Profile {
        let name: String
        let size: CGSize
        let scheme: ColorScheme
        let type: DynamicTypeSize
    }

    func testActualCoreRootsAtFixedPhoneAndIPadViewports() async throws {
        let fixture = try await RootFixture.make()
        defer { fixture.clean() }
        let profiles = [
            Profile(name: "phone-dark", size: .init(width: 393, height: 852), scheme: .dark, type: .large),
            Profile(name: "phone-light", size: .init(width: 393, height: 852), scheme: .light, type: .large),
            Profile(name: "phone-narrow", size: .init(width: 320, height: 720), scheme: .dark, type: .large),
            Profile(name: "phone-accessible", size: .init(width: 393, height: 852), scheme: .light, type: .accessibility2),
            Profile(name: "ipad-narrow", size: .init(width: 650, height: 850), scheme: .dark, type: .large),
            Profile(name: "ipad-wide", size: .init(width: 1_180, height: 820), scheme: .light, type: .large)
        ]
        for profile in profiles {
            fixture.defaults.set(profile.scheme == .dark ? "dark" : "light", forKey: FottyAppearance.storageKey)
            try await captureRoot(
                SportsDashboardView(isActive: false, matchListViewModel: fixture.catalog, myMatchdayStore: fixture.matchday),
                name: "root-home-" + profile.name, root: "SportsDashboardView", scenario: "Current listed broadcast and upcoming mixed sports; synthetic missing-art identities; real Home scope and Search controls",
                fixture: fixture, profile: profile)
            try await captureRoot(
                ArenaDiscoveryView(isActive: false, matchListViewModel: fixture.catalog, myMatchdayStore: fixture.matchday, onBrowseHome: {}),
                name: "root-matchday-" + profile.name, root: "ArenaDiscoveryView", scenario: "Full Matchday with isolated saved current/upcoming matches and genuine date/status groups",
                fixture: fixture, profile: profile)
            try await captureRoot(
                SearchView(discovery: fixture.discovery, isSaved: { fixture.matchday.contains(event: $0) },
                    canWatch: { MatchStartPolicy(event: $0, now: fixture.now).canAttemptPlayback },
                    alternateActionTitle: { _ in nil }, onOpen: { _ in XCTFail("A static Search capture must not start playback") },
                    onDetails: { _ in XCTFail("A static Search capture must not open another destination") }, onSave: { _ in .unchanged }),
                name: "root-search-prompt-" + profile.name, root: "SearchView", scenario: "Actual native Search prompt, suggestions and sport grid; no keyboard or typed-query interaction claimed",
                fixture: fixture, profile: profile)
            try await captureRoot(SettingsScreen(), name: "root-settings-" + profile.name,
                root: "SettingsScreen", scenario: "Actual Settings destinations and isolated appearance/interests; system notification status is read-only, no actions invoked",
                fixture: fixture, profile: profile)
            try await captureRoot(CatalogEventDetailsView(event: fixture.upcomingEvent, savedMatches: fixture.matchday),
                name: "root-match-details-" + profile.name, root: "CatalogEventDetailsView", scenario: "Actual upcoming match details root with long identity, countdown and existing source explanation; no save/reminder/source action invoked",
                fixture: fixture, profile: profile)
        }
    }

    func testActualSourceSheetAtFixedShortAndAccessibleViewports() async throws {
        let fixture = try await RootFixture.make()
        defer { fixture.clean() }
        let choices = ["Score808", "AS1", "AS2", "CS1"].map { provider in
            StreamSession(matchID: "design-source-only", playableURL: URL(string: "https://example.invalid/ui-only.m3u8")!,
                          streamType: .hls, providerName: provider)
        }
        for profile in [
            Profile(name: "phone", size: .init(width: 393, height: 500), scheme: .dark, type: .large),
            Profile(name: "short-accessible", size: .init(width: 320, height: 320), scheme: .dark, type: .accessibility5),
            Profile(name: "ipad", size: .init(width: 720, height: 650), scheme: .dark, type: .large)
        ] {
            try await captureRoot(
                LiveStreamSelectorSheet(sessions: choices, currentSourceIndex: .constant(1), failedSessionIDs: [choices[2].id],
                    currentPlaybackHasError: false, currentPlaybackMode: .native, isCheckingAdditionalSources: true,
                    usesSinglePlayerPresentation: true, onSelect: { _ in XCTFail("A static source-sheet capture must not select a delivery") }),
                name: "root-source-sheet-" + profile.name, root: "LiveStreamSelectorSheet",
                scenario: "Actual single-player Sources sheet: selected AS1, failed AS2, family filter and checking-more state. No player/media owner or playback proof",
                fixture: fixture, profile: profile)
        }
    }

    func testActualEmptyHomeExplainsTheSelectionBeforeBrowse() async throws {
        let fixture = try await RootFixture.make(empty: true)
        defer { fixture.clean() }
        for profile in [
            Profile(name: "phone", size: .init(width: 320, height: 720), scheme: .dark, type: .large),
            Profile(name: "ipad", size: .init(width: 1_180, height: 820), scheme: .light, type: .large)
        ] {
            try await captureRoot(
                SportsDashboardView(isActive: false, matchListViewModel: fixture.catalog, myMatchdayStore: fixture.matchday),
                name: "root-home-empty-" + profile.name, root: "SportsDashboardView",
                scenario: "Accepted genuinely empty isolated catalog; existing empty-selection recovery before Browse sports, no empty Up Next/See all heading",
                fixture: fixture, profile: profile)
        }
    }

    private func captureRoot<Content: View>(_ content: Content, name: String, root: String, scenario: String,
                                           fixture: RootFixture, profile: Profile) async throws {
        let expectedCatalogIDs = Set(fixture.events.map(\.id))
        let catalogBefore = fixture.catalog.matches.count
        let deduplicatedBefore = AnalyticalDataEngine.deduplicateMatches(fixture.catalog.matches)
        XCTAssertEqual(Set(fixture.catalog.matches.map(\.id)), expectedCatalogIDs,
                       "The isolated catalog must still own every fixture before \(name)")
        XCTAssertEqual(deduplicatedBefore.count, fixture.events.count,
                       "Fixture identity must survive the real production deduplication before \(name)")
        guard Set(fixture.catalog.matches.map(\.id)) == expectedCatalogIDs,
              deduplicatedBefore.count == fixture.events.count else { throw CaptureFailure.fixtureCatalogMissing }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { throw FottyHostedViewSnapshot.Failure.missingWindowScene }
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let view = content
            .modelContainer(fixture.container)
            .defaultAppStorage(fixture.defaults)
            .environment(fixture.scores)
            .environment(fixture.viewing)
            .environment(\.colorScheme, profile.scheme)
            .environment(\.dynamicTypeSize, profile.type)
            .environment(\.horizontalSizeClass, profile.size.width >= 600 ? .regular : .compact)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .tint(FottyTheme.accentText)
            .fottyAdaptiveWindow()
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = profile.scheme == .dark ? .dark : .light
        host.traitOverrides.preferredContentSizeCategory = category(for: profile.type)
        host.loadViewIfNeeded()
        let bounds = CGRect(origin: .zero, size: profile.size)
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.backgroundColor = .clear
        window.rootViewController = host
        defer {
            window.isHidden = true
            window.rootViewController = nil
            if previousKeyWindow?.isHidden == false { previousKeyWindow?.makeKey() }
        }
        UIView.performWithoutAnimation {
            window.makeKeyAndVisible()
            host.view.frame = bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        // Allow real bounded local projections and width observation to publish.
        // Catalog lanes are injected in-memory closures; isActive is false.
        for _ in 0..<24 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(15))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        let catalogAfter = fixture.catalog.matches.count
        let deduplicatedAfter = AnalyticalDataEngine.deduplicateMatches(fixture.catalog.matches)
        XCTAssertEqual(Set(fixture.catalog.matches.map(\.id)), expectedCatalogIDs,
                       "A static root must not erase or substitute the isolated catalog during \(name)")
        XCTAssertEqual(deduplicatedAfter.count, fixture.events.count,
                       "Fixture identity must survive production deduplication after \(name)")
        guard Set(fixture.catalog.matches.map(\.id)) == expectedCatalogIDs,
              deduplicatedAfter.count == fixture.events.count else { throw CaptureFailure.fixtureCatalogMissing }
        XCTAssertEqual(host.view.bounds.width, profile.size.width, accuracy: 0.5)
        XCTAssertEqual(host.view.bounds.height, profile.size.height, accuracy: 0.5)
        CATransaction.flush()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        var complete = false
        let image = UIGraphicsImageRenderer(size: profile.size, format: format).image { _ in
            complete = host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(complete, "Native root hierarchy must finish: \(name)")
        XCTAssertEqual(image.size, profile.size)
        let pixels = try FottyVisualPixelComparison.Pixels(image: image)
        XCTAssertGreaterThan(Set(pixels.rgba).count, 16, "Reject a blank root capture")
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let insets = host.view.safeAreaInsets
        let metadata: [String: Any] = [
            "schemaVersion": 1, "kind": "production-root-static-native-host", "root": root,
            "scenario": scenario, "renderer": "UIHostingController.drawHierarchy.fixedViewport.v1",
            "width": Int(profile.size.width), "height": Int(profile.size.height),
            "appearance": profile.scheme == .dark ? "dark" : "light", "textSize": String(describing: profile.type),
            "safeAreaInsets": ["top": Double(insets.top), "left": Double(insets.left), "bottom": Double(insets.bottom), "right": Double(insets.right)],
            "fixtureClockUTC": ISO8601DateFormatter().string(from: fixture.now),
            "clockQualification": "Fixtures are pinned to this run's captured clock; production controls retain their current Date clock. Not a deterministic golden baseline.",
            "captureUTC": ISO8601DateFormatter().string(from: Date()),
            "catalogBefore": catalogBefore, "catalogAfter": catalogAfter,
            "deduplicatedBefore": deduplicatedBefore.count, "deduplicatedAfter": deduplicatedAfter.count,
            "catalogContentRevision": fixture.catalog.contentRevision,
            "discoveryItemsAtCapture": HomeSportsDiscovery(events: fixture.catalog.matches, now: Date()).items.count,
            "automatedHomeClockUTC": HomeSportsDiscovery.automatedClockStart.map { ISO8601DateFormatter().string(from: $0) } ?? "not enabled",
            "platform": "Fresh test host; operator records actual build/OS/executable provenance separately",
            "hostUserInterfaceIdiomRawValue": UIDevice.current.userInterfaceIdiom.rawValue,
            "viewportQualification": "Phone-width profiles constrain the native host window, not UIDevice idiom; they are not physical phone evidence.",
            "limitations": ["Not a physical phone/iPad screenshot", "No physical keyboard/touch/VoiceOver or native playback proof", "Host safe areas and glyph/material behavior differ from iOS", "Synthetic identities test missing-art layout, not crest fidelity"]
        ]
        try write(image: image, metadata: metadata, name: name)
    }

    private func write(image: UIImage, metadata: [String: Any], name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["FOTTY_25_UI_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path).standardizedFileURL
        let ownedPrefix = directory.path.hasPrefix("/private/tmp/Fotty25UI.") || directory.path.hasPrefix("/tmp/Fotty25UI.")
        guard ownedPrefix,
              directory.resolvingSymlinksInPath().path == directory.path,
              FileManager.default.fileExists(atPath: directory.path),
              name.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else {
            XCTFail("Only the owned temporary UI gate may receive captures"); return
        }
        for ext in ["png", "json"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name + "." + ext).path),
                           "Never overwrite capture evidence")
        }
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"), options: .withoutOverwriting)
    }

    private func category(for type: DynamicTypeSize) -> UIContentSizeCategory {
        switch type {
        case .accessibility2: return .accessibilityLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        default: return .large
        }
    }

    @MainActor
    private final class RootFixture {
        let suite: String
        let defaults: UserDefaults
        let container: ModelContainer
        let matchday: MyMatchdayStore
        let catalog: MatchListViewModel
        let scores: LiveScoreService
        let viewing: ViewingSessionCoordinator
        let now: Date
        let events: [EventReference]
        var upcomingEvent: EventReference { events[1] }
        var discovery: HomeSportsDiscovery { .init(events: events, now: now) }

        private init(suite: String, defaults: UserDefaults, container: ModelContainer, matchday: MyMatchdayStore,
                     catalog: MatchListViewModel, scores: LiveScoreService, viewing: ViewingSessionCoordinator,
                     now: Date, events: [EventReference]) {
            self.suite = suite; self.defaults = defaults; self.container = container
            self.matchday = matchday; self.catalog = catalog; self.scores = scores
            self.viewing = viewing; self.now = now; self.events = events
        }

        static func make(empty: Bool = false) async throws -> RootFixture {
            let suite = "Fotty25.RootRender.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let schema = LocalDataStore.appSchema
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            let now = Date()
            func event(_ id: String, _ home: String, _ away: String, _ sport: String, _ offset: TimeInterval, listed: Bool = false) -> EventReference {
                .init(id: "root-render-" + id, title: "\(home) vs \(away)", category: sport,
                      date: Int64(now.addingTimeInterval(offset).timeIntervalSince1970), poster: nil, popular: false,
                      teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)),
                      sources: listed ? [.init(source: "delta", id: "root-render-only")] : [])
            }
            let events: [EventReference] = empty ? [] : [
                event("football-now", "Render Alpha Club", "Render Visiting Club", "football", -1_800, listed: true),
                event("cricket-next", "Render Women's International Representative Team", "Render Visiting International Representative Team", "cricket", 3_600),
                event("football-next", "Render Northern Football Club", "Render Southern Football Club", "football", 7_200),
                event("baseball", "Render Baseball A", "Render Baseball B", "baseball", 10_800),
                event("hockey", "Render Hockey A", "Render Hockey B", "hockey", 14_400),
                event("basketball", "Render Basketball A", "Render Basketball B", "basketball", 18_000),
                event("football-later", "Render Under 19 A", "Render Under 19 B", "football", 90_000)
            ]
            defaults.set("[]", forKey: SportsInterestPreferences.storageKey)
            defaults.set(false, forKey: HomeInterestPreferences.onlyShowSelectedKey)
            defaults.set(false, forKey: MatchdayPreferences.showKickoffClashesKey)
            let matchday = MyMatchdayStore(defaults: defaults)
            for event in events { XCTAssertEqual(matchday.save(event), .saved) }
            // Home has no provider catalog; the render fixture seeds its rows directly.
            let catalog = MatchListViewModel(now: { now }, matchdayStore: matchday)
            catalog.configure(modelContext: container.mainContext)
            catalog.matches = events
            XCTAssertEqual(catalog.matches.count, events.count)
            let scores = LiveScoreService(now: { now })
            let viewing = ViewingSessionCoordinator(catalogEvent: { $0.preferredEvent }, cancelPlayback: { _ in })
            return RootFixture(suite: suite, defaults: defaults, container: container, matchday: matchday,
                               catalog: catalog, scores: scores, viewing: viewing, now: now, events: events)
        }

        func clean() {
            viewing.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
