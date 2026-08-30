import XCTest
import SwiftUI
import UserNotifications
@testable import Fotty

@MainActor
final class MatchReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ id: String = "match", start: Date?, source: Bool = true, channel: Bool = false) -> AnalyticalDataEngine.EventReference {
        .init(id: id, title: channel ? "Willow Cricket" : "Home Club vs Away Club", category: channel ? "cricket" : "football",
              date: start.map { Int64($0.timeIntervalSince1970) }, poster: nil, popular: nil, teams: nil,
              sources: source ? [.init(source: "delta", id: id)] : [])
    }

    private func harness() throws -> ReminderHarness { try ReminderHarness(now: now) }

    func testCountdownAndPlayBoundaries() {
        for (seconds, canPlay, title) in [(7200.0, false, "Starts in 2h 0m"), (301, false, "Starts in 6m"),
            (300, false, "Starts in 5:00"), (121, false, "Starts in 2:01"), (120, true, "Starts in 2:00"),
            (1, true, "Starts in 0:01"), (0, true, "Watch")] {
            let policy = MatchStartPolicy(event: event(start: now.addingTimeInterval(seconds)), now: now)
            XCTAssertEqual(policy.canAttemptPlayback, canPlay, "\(seconds)")
            XCTAssertEqual(policy.title, title)
        }
        XCTAssertEqual(MatchStartPolicy.countdown(86_400 + 7200), "1d 2h")
        XCTAssertEqual(MatchStartPolicy.countdown(0.01), "0:01")
    }

    func testChannelsUnknownTimesAndSourceFreeSchedulesRemainHonest() {
        let channel = event(start: now.addingTimeInterval(7200), channel: true)
        XCTAssertNil(MatchStartPolicy(event: channel, now: now).upcomingStart)
        XCTAssertTrue(MatchStartPolicy(event: channel, now: now).canAttemptPlayback)
        XCTAssertNil(MatchReminderRecord.make(event: channel, now: now))
        let unknown = event(start: nil)
        XCTAssertNil(MatchStartPolicy(event: unknown, now: now).upcomingStart)
        XCTAssertEqual(MatchStartPolicy(event: unknown, now: now).title, "Check streams")
        XCTAssertNil(MatchReminderRecord.make(event: unknown, now: now))
        let noSource = event(start: now.addingTimeInterval(120), source: false)
        XCTAssertFalse(MatchStartPolicy(event: noSource, now: now).canAttemptPlayback)
        XCTAssertEqual(MatchStartPolicy(event: noSource, now: now).title, "Starts in 2:00")
    }

    func testOfficialStoppedStatusOverridesTimerButLiveCanOverrideFutureCatalog() {
        let match = event(start: now.addingTimeInterval(3600))
        for status: FootballMatch.MatchStatus in [.cancelled, .postponed, .suspended, .finished, .awarded] {
            let policy = MatchStartPolicy(event: match, now: now, status: status)
            XCTAssertNil(policy.upcomingStart)
            XCTAssertFalse(policy.canAttemptPlayback)
        }
        let live = MatchStartPolicy(event: match, now: now, status: .inPlay)
        XCTAssertTrue(live.canAttemptPlayback)
        XCTAssertNil(live.upcomingStart)
    }

    func testClockEntersPreciseWindowAndStopsSecondTicksAtStart() {
        let dates = Array(MatchCountdownSchedule(kickoff: now.addingTimeInterval(302))
            .entries(from: now, mode: .normal).prefix(5))
        XCTAssertEqual(dates.map { $0.timeIntervalSince(now) }, [0, 2, 3, 4, 5])
        let end = Array(MatchCountdownSchedule(kickoff: now.addingTimeInterval(1))
            .entries(from: now, mode: .normal).prefix(3))
        XCTAssertEqual(end.map { $0.timeIntervalSince(now) }, [0, 1, 61])
    }

    func testNotificationUsesAbsoluteUTCAndSafeMatchdayPayload() throws {
        let record = try XCTUnwrap(MatchReminderRecord.make(event: event("match/with spaces", start: now.addingTimeInterval(900)), now: now))
        let request = record.request
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(trigger.dateComponents.date, now.addingTimeInterval(600))
        XCTAssertEqual(request.content.userInfo["route"] as? String, "match-reminder")
        XCTAssertEqual(request.content.userInfo["matchID"] as? String, "match/with spaces")
        XCTAssertTrue(request.content.body.contains("scheduled to start in 5 minutes"))
        XCTAssertFalse(request.content.body.contains("watch now"))
        XCTAssertNotEqual(MatchReminderRecord.requestID(eventID: "a/b"), MatchReminderRecord.requestID(eventID: "ab"))
    }

    func testSavingAloneIsSilentAndExplicitReminderPersistsOnce() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        h.matchday.save(match)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 0)
        let result = await h.store.enable(match)
        XCTAssertEqual(result, .scheduled)
        XCTAssertTrue(h.matchday.contains(eventID: match.id))
        _ = await h.store.enable(match)
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertEqual(h.store.records.count, 1)
        let restored = MatchReminderStore(defaults: h.defaults, client: h.client, matchday: h.matchday, clock: { h.clock.now })
        XCTAssertTrue(restored.contains(match.id))
        await restored.reconcile(events: [match])
        XCTAssertEqual(h.client.requests.count, 1)
        h.store.cancel(match.id)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.matchday.contains(eventID: match.id), "Bell cancellation must not remove the bookmark")
    }

    func testDeniedPermissionDoesNotClaimReminderOrSaveMatch() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .denied
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .denied)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.matchday.savedMatches.isEmpty)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 0)
    }

    func testPermissionPromptOnlyFollowsOptInAndLatePermissionDoesNotScheduleOverdueAlert() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .notDetermined
        let match = event(start: now.addingTimeInterval(600))
        await h.store.reconcile(events: [match])
        XCTAssertEqual(h.client.prompts, 0)
        h.client.onPrompt = { h.clock.now = self.now.addingTimeInterval(301) }
        let result = await h.store.enable(match)
        XCTAssertEqual(result, .tooLate)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.client.prompts, 1)
    }

    func testLateUnknownAndChannelOptInsNeverGenerateImmediateNotifications() async throws {
        let h = try harness(); defer { h.clean() }
        for match in [event(start: now.addingTimeInterval(300)), event(start: now.addingTimeInterval(-60)),
            event(start: nil), event(start: now.addingTimeInterval(7200), channel: true)] {
            let result = await h.store.enable(match)
            XCTAssertEqual(result, .tooLate)
        }
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testCancellationDuringPermissionCannotResurrectReminder() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .notDetermined
        h.client.onPrompt = { h.store.cancel("match") }
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.records.isEmpty)
        XCTAssertTrue(h.matchday.savedMatches.isEmpty)
    }

    func testCancelBeforePermissionCheckReturnsDoesNotShowSystemPrompt() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.permission = .notDetermined
        h.client.onStatus = { h.store.cancel("match") }
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(h.client.prompts, 0)
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testCancellationWhileSystemAddIsInFlightRemovesLateCompletion() async throws {
        let h = try harness(); defer { h.clean() }
        h.client.onAdd = { _ in h.store.cancel("match") }
        let result = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.records.isEmpty)
    }

    func testUnsaveRevokesReminderWithoutTouchingOtherMatches() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event("one", start: now.addingTimeInterval(7200)))
        _ = await h.store.enable(event("two", start: now.addingTimeInterval(7200)))
        h.matchday.remove(eventID: "one")
        XCTAssertFalse(h.store.contains("one"))
        XCTAssertFalse(h.matchday.contains(eventID: "one"))
        XCTAssertTrue(h.store.contains("two"))
        XCTAssertEqual(h.client.requests.count, 1)
    }

    func testCancellationDuringRescheduleCannotRecreateSystemRequest() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        h.client.onAdd = { _ in h.store.cancel("match") }
        await h.store.reconcile(events: [event(start: now.addingTimeInterval(10_800))])
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.records.isEmpty)
    }

    func testEarlierRescheduleSkipsMissedReminderAndUnknownTimeRevokesIt() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        await h.store.reconcile(events: [event(start: now.addingTimeInterval(240))])
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertEqual(h.store.records.first?.fireDate, now.addingTimeInterval(-60))
        await h.store.reconcile(events: [event(start: nil)])
        XCTAssertTrue(h.store.records.isEmpty)
    }

    func testConcurrentOptInsConvergeToOneRequest() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        async let first = h.store.enable(match)
        async let second = h.store.enable(match)
        _ = await (first, second)
        XCTAssertEqual(h.store.records.count, 1)
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertTrue(h.store.busyIDs.isEmpty)
    }

    func testRescheduleReplacesRequestUpdatesSavedSnapshotAndDoesNotDuplicate() async throws {
        let h = try harness(); defer { h.clean() }
        _ = await h.store.enable(event(start: now.addingTimeInterval(7200)))
        let changed = event(start: now.addingTimeInterval(10_800))
        await h.store.reconcile(events: [changed])
        XCTAssertEqual(h.client.requests.count, 1)
        XCTAssertEqual(h.store.records.first?.fireDate, now.addingTimeInterval(10_500))
        XCTAssertEqual(h.matchday.savedMatches.first?.event.kickoffDate, changed.kickoffDate)
        let adds = h.client.adds
        await h.store.reconcile(events: [changed])
        XCTAssertEqual(h.client.adds, adds, "An unchanged catalog refresh must not reschedule the same alert")
    }

    func testPostponedCancelledAndAlreadyLiveMatchesRevokePendingReminder() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        for status: FootballMatch.MatchStatus in [.postponed, .cancelled, .inPlay, .finished] {
            _ = await h.store.enable(match)
            await h.store.reconcile(events: []) { _ in status }
            XCTAssertTrue(h.client.requests.isEmpty)
            XCTAssertFalse(h.store.contains(match.id))
        }
    }

    func testMissingCatalogIsNotCancellationAndRelaunchDoesNotRecreateDueAlert() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        _ = await h.store.enable(match)
        await h.store.reconcile(events: [])
        XCTAssertTrue(h.store.contains(match.id))
        XCTAssertEqual(h.client.requests.count, 1)
        h.clock.now = now.addingTimeInterval(7000)
        h.client.requests.removeAll() // the system has fired the alert
        await h.store.reconcile(events: [])
        XCTAssertTrue(h.client.requests.isEmpty)
    }

    func testRevokedPermissionAndFailedSchedulingRemainTruthful() async throws {
        let h = try harness(); defer { h.clean() }
        let match = event(start: now.addingTimeInterval(7200))
        h.client.failAdd = true
        let failed = await h.store.enable(match)
        XCTAssertEqual(failed, .failed)
        XCTAssertFalse(h.store.contains(match.id))
        h.client.failAdd = false
        _ = await h.store.enable(match)
        h.client.permission = .denied
        await h.store.reconcile(events: [])
        XCTAssertFalse(h.store.notificationsAllowed)
        XCTAssertTrue(h.client.requests.isEmpty)
        XCTAssertTrue(h.store.contains(match.id), "Retain explicit intent, but never show it as deliverable with permission off")
        h.client.permission = .authorized
        await h.store.reconcile(events: [])
        XCTAssertEqual(h.client.requests.count, 1)
    }

    func testReminderCapLeavesRoomForFPLAndNeverRemovesUnrelatedNotifications() async throws {
        let h = try harness(); defer { h.clean() }
        let fpl = UNNotificationRequest(identifier: "fotty.fpl.deadline.2.120", content: UNMutableNotificationContent(), trigger: nil)
        h.client.requests[fpl.identifier] = fpl
        for index in 0..<MatchReminderStore.maximumReminders {
            let result = await h.store.enable(event("m\(index)", start: now.addingTimeInterval(7200)))
            XCTAssertEqual(result, .scheduled)
        }
        let overflow = await h.store.enable(event("overflow", start: now.addingTimeInterval(7200)))
        XCTAssertEqual(overflow, .limitReached)
        await h.store.reconcile(events: [])
        XCTAssertNotNil(h.client.requests[fpl.identifier])
        XCTAssertEqual(h.client.requests.count, MatchReminderStore.maximumReminders + 1)
    }

    func testReminderRouteTargetsMatchdayNotPlayerOrMatchCenter() throws {
        let navigation = MatchNavigationStore.shared
        defer { navigation.pendingMatchID = nil; navigation.pendingReminderID = nil }
        let url = try XCTUnwrap(URL(string: "fotty://matchday/catalog-123"))
        XCTAssertEqual(FottyDeepLinkDestination.parse(url), .matchday("catalog-123"))
        navigation.pendingMatchID = "old"
        navigation.open(url: url)
        XCTAssertEqual(navigation.pendingReminderID, "catalog-123")
        XCTAssertNil(navigation.pendingMatchID)
        XCTAssertNil(navigation.activeLivePlayerMatchID)
    }

    func testMatchCenterCannotBeginPrematureResolutionEvenViaDirectAction() {
        let match = event(start: Date().addingTimeInterval(7200))
        let model = MatchHubViewModel(testEvent: match)
        model.watchLive()
        XCTAssertFalse(model.isFindingStream)
        XCTAssertFalse(model.showPlayer)
        XCTAssertNil(model.playerEvent)
        XCTAssertTrue(model.streamSessions.isEmpty)
    }

    func testFailureFeedbackIsPerEventAndExplicitRetryClearsIt() {
        let feedback = MatchPlaybackFeedback()
        feedback.notReady("one")
        XCTAssertFalse(feedback.notReadyIDs.contains("two"))
        feedback.attempting("one")
        XCTAssertTrue(feedback.notReadyIDs.isEmpty)
    }

    func testCountdownControlsRenderNonblankInBothModesAndNarrowLargeText() throws {
        for (width, scheme, size) in [(320.0, ColorScheme.dark, DynamicTypeSize.large),
            (375.0, .dark, .large), (375.0, .light, .large),
            (375.0, .light, .accessibility2), (820.0, .dark, .large), (820.0, .light, .large)] {
            let content = VStack(alignment: .leading, spacing: 14) {
                Text("Now & next").font(FottyTheme.typeSectionTitle).foregroundStyle(FottyTheme.textPrimary)
                ForEach([7200.0, 280, 110, -10], id: \.self) { offset in
                    let match = self.event("qa-\(offset)", start: Date().addingTimeInterval(offset))
                    if let item = HomeSportsDiscovery(events: [match]).items.first {
                        HomeDiscoveryRow(item: item, isSaved: false, onOpen: {}, onSave: {})
                            .environment(LiveScoreService.shared)
                    }
                    Divider()
                }
            }
            .padding(16).frame(width: width)
            .background(FottyTheme.background)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertLessThan(image.size.height, 2200)
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16)
            let attachment = XCTAttachment(image: image)
            attachment.name = "countdown-\(Int(width))-\(scheme)-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCompactRowOnlyStacksWhenWidthOrAccessibilityRequiresIt() {
        XCTAssertTrue(MatchRowLayout.fitsBeside(width: 250, informationMinimum: 150, actionWidth: 88))
        XCTAssertFalse(MatchRowLayout.fitsBeside(width: 249, informationMinimum: 150, actionWidth: 88))
        XCTAssertTrue(MatchRowLayout.fitsBeside(width: 343, informationMinimum: 150, actionWidth: 140))
        XCTAssertTrue(MatchRowLayout.fitsBeside(width: 788, informationMinimum: 150, actionWidth: 140))
        XCTAssertFalse(MatchRowLayout.fitsBeside(width: 788, informationMinimum: 150, actionWidth: 88, forceStack: true))
    }

    func testActualHomeAndLineupKeepWatchOnTheRightWithoutAnExtraStrip() throws {
        for width in [320.0, 375, 820] {
            for scheme: ColorScheme in [.light, .dark] {
                let match = event("compact-live", start: Date().addingTimeInterval(-10))
                let item = try XCTUnwrap(HomeSportsDiscovery(events: [match]).items.first)
                let rows = [
                    AnyView(HomeDiscoveryRow(item: item, isSaved: false, onOpen: {}, onSave: {})),
                    AnyView(LiveEventCard(event: match, onWatchTap: {}, onSaveTap: {})),
                    AnyView(LiveEventCard(event: event("compact-channel", start: nil, channel: true), onWatchTap: {}, onSaveTap: {}))
                ]
                for (index, row) in rows.enumerated() {
                    let renderer = ImageRenderer(content: row.padding(.horizontal, 16).frame(width: width)
                        .background(FottyTheme.background).environment(LiveScoreService.shared)
                        .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .large))
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertLessThan(image.size.height, 150, "Normal live rows must not reserve another action strip")
                    let gold = try accentBounds(in: image)
                    XCTAssertGreaterThan(gold.minX, width * 0.55, "Watch must be beside, not below, the teams")
                    XCTAssertEqual(gold.midY, image.size.height / 2, accuracy: 3)
                    XCTAssertGreaterThanOrEqual(gold.height, 43)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "compact-\(["home", "lineup", "channel"][index])-\(Int(width))-\(scheme)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testLineupRendersUpcomingLongNamesChannelsAndLargeText() throws {
        for (width, size) in [(343.0, DynamicTypeSize.large), (343.0, .accessibility2), (788.0, .large)] {
            let longMatch = AnalyticalDataEngine.EventReference(id: "compact-cpl",
                title: "St Kitts and Nevis Patriots vs Trinbago Knight Riders", category: "cricket",
                date: Int64(Date().addingTimeInterval(7200).timeIntervalSince1970), poster: nil,
                popular: nil, teams: nil, sources: [])
            let content = VStack(spacing: 12) {
                LiveEventCard(event: longMatch, onSaveTap: {})
                LiveEventCard(event: event("channel", start: nil, channel: true), onWatchTap: {}, onSaveTap: {})
            }
            .padding(16).frame(width: width).background(FottyTheme.background)
            .environment(LiveScoreService.shared).environment(\.dynamicTypeSize, size).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertLessThan(image.size.height, 1000)
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16)
            let attachment = XCTAttachment(image: image)
            attachment.name = "compact-variety-\(Int(width))-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func accentBounds(in image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<height {
            var runStart: Int?
            for x in 0...width {
                let offset = (y * width + x) * 4
                let isGold = x < width && pixels[offset] > 220 && pixels[offset + 1] > 140
                    && pixels[offset + 1] < 230 && pixels[offset + 2] < 90 && pixels[offset + 3] > 240
                if isGold {
                    if runStart == nil { runStart = x }
                } else if let start = runStart {
                    // Identify the filled button, not gold LIVE text or badge
                    // details. Its continuous fill is wider than any glyph.
                    if x - start >= 32 { xs += [start, x - 1]; ys.append(y) }
                    runStart = nil
                }
            }
        }
        let x = try XCTUnwrap(xs.min()), y = try XCTUnwrap(ys.min())
        return CGRect(x: x, y: y, width: try XCTUnwrap(xs.max()) - x + 1, height: try XCTUnwrap(ys.max()) - y + 1)
    }

    func testUpcomingHomeInformationIsNotRenderedAsADisabledButton() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fotty/Features/Dashboard/Components/SportsDiscoveryViews.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains(".disabled(!MatchStartPolicy"))
        XCTAssertTrue(source.contains("A future fixture is readable information"))
    }
}

@MainActor
private final class ReminderClock { var now: Date; init(_ now: Date) { self.now = now } }

@MainActor
private final class ReminderHarness {
    let suite = "FottyTests.Reminders.\(UUID().uuidString)"
    let defaults: UserDefaults
    let client = FakeReminderNotifications()
    let matchday: MyMatchdayStore
    let clock: ReminderClock
    let store: MatchReminderStore
    init(now: Date) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        matchday = MyMatchdayStore(defaults: defaults)
        clock = ReminderClock(now)
        let clock = self.clock
        store = MatchReminderStore(defaults: defaults, client: client, matchday: matchday, clock: { clock.now })
        let reminderStore = store
        matchday.onRemove = { [weak reminderStore] in reminderStore?.cancel($0) }
    }
    func clean() {
        client.onPrompt = nil
        client.onAdd = nil
        client.onStatus = nil
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class FakeReminderNotifications: MatchReminderNotificationClient {
    var permission: UNAuthorizationStatus = .authorized
    var requests: [String: UNNotificationRequest] = [:]
    var prompts = 0
    var adds = 0
    var failAdd = false
    var onPrompt: (() -> Void)?
    var onStatus: (() -> Void)?
    var onAdd: ((UNNotificationRequest) -> Void)?
    func authorizationStatus() async -> UNAuthorizationStatus { onStatus?(); return permission }
    func requestAuthorization() async throws -> Bool {
        prompts += 1
        onPrompt?()
        permission = .authorized
        return true
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws {
        adds += 1
        onAdd?(request)
        if failAdd { throw NSError(domain: "ReminderTest", code: 1) }
        requests[request.identifier] = request
    }
    func remove(_ identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
}
