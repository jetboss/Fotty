import AVFoundation
import XCTest
@testable import Fotty

/// Isolated policy/ownership tests. Items reference /dev/null and metadata is
/// injected: no remote manifest, media decoding or physical playback is claimed.
@MainActor
final class SinglePlaybackQualityTests: XCTestCase {
    private typealias Variant = SinglePlaybackQualityPolicy.Variant

    func testAdvancingItemDateMeasuresAdvertisedMediaAgeWithoutClaimingEventDelay() {
        var clock = SinglePlaybackMediaClock(first: clockSample(0, programme: -130))
        clock.observe(clockSample(15, programme: -115))
        clock.observe(clockSample(30, programme: -100))
        XCTAssertEqual(clock.advertisedAgeMilliseconds, 130_000)
        let details = SinglePlaybackMediaClock.qualityDetails(web: false, advertisedAgeMilliseconds: clock.advertisedAgeMilliseconds)
        XCTAssertEqual(details["media_clock_evidence"], "advertised_item_date")
        XCTAssertEqual(details["advertised_media_age_ms"], "130000")
        XCTAssertEqual(details["live_event_delay_evidence"], "unmeasured")
        XCTAssertNil(SinglePlaybackMediaClock.qualityDetails(web: true, advertisedAgeMilliseconds: 0)["advertised_media_age_ms"])
    }

    func testMissingMappingClockResetRestampedJumpAndUnusableDatesRemainUnknown() {
        for invalid in [clockSample(15, programme: nil), clockSample(15, programme: -130),
                        clockSample(15, programme: 16), clockSample(15, programme: -100_000),
                        clockSample(15, programme: -115, wall: 30)] {
            var clock = SinglePlaybackMediaClock(first: clockSample(0, programme: -130))
            clock.observe(invalid)
            clock.observe(clockSample(30, programme: -100))
            XCTAssertNil(clock.advertisedAgeMilliseconds)
        }
        var unanchored = SinglePlaybackMediaClock(first: clockSample(0, programme: nil))
        unanchored.observe(clockSample(15, programme: -115))
        XCTAssertNil(unanchored.advertisedAgeMilliseconds)
    }

    private func clockSample(_ seconds: TimeInterval, programme: TimeInterval?,
                             wall: TimeInterval? = nil) -> SinglePlaybackMediaClock.Sample {
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        return .init(uptime: seconds, wall: epoch.addingTimeInterval(wall ?? seconds), media: seconds,
                     programme: programme.map { epoch.addingTimeInterval($0) })
    }

    func testAccessLogRenditionSwitchCanSustainButStallResetOrReplacedHistoryCannot() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SinglePlaybackAccessEvent(began: start, stalls: 1)
        let next = SinglePlaybackAccessEvent(began: start.addingTimeInterval(10), stalls: 0)
        XCTAssertTrue(SinglePlaybackAccessEvent.uninterrupted(previous: [first], current: [first, next]))
        XCTAssertFalse(SinglePlaybackAccessEvent.uninterrupted(previous: [first], current: [next]))
        XCTAssertFalse(SinglePlaybackAccessEvent.uninterrupted(previous: [first], current: [first, .init(began: next.began, stalls: 1)]))
        XCTAssertFalse(SinglePlaybackAccessEvent.uninterrupted(previous: [first], current: nil))
        XCTAssertTrue(SinglePlaybackAccessEvent.uninterrupted(previous: nil, current: nil))
    }

    private var ladder: [Variant] {
        [variant(500_000, width: 640, height: 360), variant(1_200_000, width: 960, height: 540),
         variant(4_000_000, width: 1920, height: 1080)]
    }

    private func variant(_ rate: Double, width: Double = 1280, height: Double = 720,
                         average: Double = -1) -> Variant {
        .init(peakBitRate: rate, averageBitRate: average, width: width, height: height)
    }

    private func item() -> AVPlayerItem {
        ReadyQualityItem(asset: AVURLAsset(url: URL(fileURLWithPath: "/dev/null")))
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("The bounded quality inspection did not reach its expected state", file: file, line: line)
    }

    private func model(controller: SinglePlaybackQualityController, web: Bool = false,
                       configureSingle: Bool = true, alternatives: Bool = false) -> LivePlayerViewModel {
        let event = EventReference(id: "quality-test", title: "Liverpool vs Chelsea", category: "football",
            date: Int64(Date().timeIntervalSince1970) - 60, poster: nil, popular: false, teams: nil, sources: [])
        let first = StreamSession(matchID: event.id,
            playableURL: URL(string: web ? "https://example.invalid/embed/quality" : "https://example.invalid/master.m3u8")!,
            streamType: web ? .unknown : .hls, providerName: "AS1",
            requiredHeaders: web ? ["X-Fotty-Web-Embed": "true"] : [:], qualityLabel: "HD")
        let second = StreamSession(matchID: event.id, playableURL: URL(string: "https://example.invalid/second.m3u8")!,
            streamType: .hls, providerName: "AS2")
        let model = LivePlayerViewModel(event: event, providedSessions: alternatives ? [first, second] : [first],
            ownsRemoteCommands: false,
            prepareAudioSession: { XCTFail("Quality changes must not activate audio"); return .completed([]) },
            configureAudioSession: { XCTFail("Quality changes must not configure audio"); return .completed([]) },
            singlePlaybackQuality: controller)
        if configureSingle { XCTAssertTrue(model.configureSingleStreamRanking()) }
        return model
    }

    private func confirm(_ model: LivePlayerViewModel) throws {
        let source = try XCTUnwrap(model.activeSource)
        model.recordPlaybackStage(.decoded, sourceID: source.id, requestID: model.loadRequestID)
    }

    func testFixedUnknownAudioOnlyAndDuplicateVariantMetadataCannotOfferAQualityChoice() {
        for values in [[], [variant(1_000_000)], [variant(1_000_000), variant(1_000_000)],
                       [variant(500_000, width: 0), variant(2_000_000, height: 0)],
                       [variant(-1), variant(.nan)], [variant(500_000, width: .infinity), variant(3_000_000)]] {
            XCTAssertNil(SinglePlaybackQualityPolicy.dataSaverLimit(variants: values))
        }
    }

    func testDataSaverUsesAnActuallyDeclaredLowerTierAndDoesNotInventAResolution() throws {
        let limit = try XCTUnwrap(SinglePlaybackQualityPolicy.dataSaverLimit(variants: ladder))
        XCTAssertEqual(limit.peakBitRate, 1_200_000)
        XCTAssertEqual(limit.maximumResolution, CGSize(width: 960, height: 540))
        let alreadySmall = try XCTUnwrap(SinglePlaybackQualityPolicy.dataSaverLimit(variants: [variant(300_000), variant(800_000)]))
        XCTAssertEqual(alreadySmall.peakBitRate, 300_000, "The second choice must differ from unrestricted Auto")
        let highOnly = try XCTUnwrap(SinglePlaybackQualityPolicy.dataSaverLimit(variants: [variant(2_000_000), variant(6_000_000)]))
        XCTAssertEqual(highOnly.peakBitRate, 2_000_000, "Never fabricate a lower rendition that the source did not declare")
    }

    func testDataSaverHonorsOriginalCeilingsAndRejectsAnIdenticalChoice() throws {
        XCTAssertNil(SinglePlaybackQualityPolicy.dataSaverLimit(variants: ladder, originalPeakBitRate: 400_000))
        let lower = try XCTUnwrap(SinglePlaybackQualityPolicy.dataSaverLimit(variants: ladder, originalPeakBitRate: 1_000_000))
        XCTAssertEqual(lower.peakBitRate, 500_000)
        XCTAssertEqual(SinglePlaybackQualityPolicy.constrainedResolution(CGSize(width: 1280, height: 720),
            original: CGSize(width: 960, height: 540)), CGSize(width: 960, height: 540))
        XCTAssertEqual(SinglePlaybackQualityPolicy.constrainedResolution(CGSize(width: 640, height: 360), original: .zero),
            CGSize(width: 640, height: 360))
    }

    func testMissingPeakMayUseDeclaredAverageButUnknownAndNonfiniteRatesStayUnsupported() throws {
        let limit = try XCTUnwrap(SinglePlaybackQualityPolicy.dataSaverLimit(variants: [
            variant(-1, average: 600_000), variant(3_000_000), variant(.infinity), variant(-1, average: .nan)]))
        XCTAssertEqual(limit.peakBitRate, 600_000)
    }

    func testAutoLeavesExistingItemPreferencesUntouchedAndRestoresThemAfterDataSaver() async throws {
        let variants = ladder
        let controller = SinglePlaybackQualityController(loadVariants: { _ in variants })
        let item = item(), player = AVPlayer()
        item.preferredPeakBitRate = 3_000_000
        item.preferredMaximumResolution = CGSize(width: 1600, height: 900)
        player.replaceCurrentItem(with: item)
        let source = UUID(), request = UUID()
        controller.inspect(player: player, item: item, sourceID: source, requestID: request, isCurrent: { true })
        defer { controller.invalidate(); player.replaceCurrentItem(with: nil) }
        await waitFor { controller.isAvailable }

        XCTAssertEqual(controller.preference, .auto)
        XCTAssertEqual(item.preferredPeakBitRate, 3_000_000)
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 1600, height: 900))
        XCTAssertTrue(controller.select(.dataSaver))
        XCTAssertEqual(item.preferredPeakBitRate, 1_200_000)
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 960, height: 540))
        XCTAssertTrue(controller.select(.auto))
        XCTAssertEqual(item.preferredPeakBitRate, 3_000_000)
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 1600, height: 900))
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(player.rate, 0)
    }

    func testMetadataFailureDoesNotExposeAnUnsupportedControlOrChangeTheItem() async {
        enum Failure: Error { case unavailable }
        var calls = 0
        let controller = SinglePlaybackQualityController(loadVariants: { _ in calls += 1; throw Failure.unavailable })
        let item = item(), player = AVPlayer()
        player.replaceCurrentItem(with: item)
        let source = UUID(), request = UUID()
        controller.inspect(player: player, item: item, sourceID: source, requestID: request, isCurrent: { true })
        defer { controller.invalidate(); player.replaceCurrentItem(with: nil) }
        await waitFor { calls == 1 }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(controller.isAvailable)
        XCTAssertFalse(controller.select(.dataSaver))
        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        controller.inspect(player: player, item: item, sourceID: source, requestID: request, isCurrent: { true })
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(calls, 1, "A redraw cannot repeatedly inspect an unavailable capability")
    }

    func testLateCapabilityResultIsFencedAfterInvalidation() async {
        let gate = VariantGate()
        let controller = SinglePlaybackQualityController(loadVariants: { _ in await gate.load() })
        let item = item(), player = AVPlayer()
        player.replaceCurrentItem(with: item)
        controller.inspect(player: player, item: item, sourceID: UUID(), requestID: UUID(), isCurrent: { true })
        defer { gate.finishAll(); controller.invalidate(); player.replaceCurrentItem(with: nil) }
        await waitFor { gate.pending.count == 1 }
        controller.invalidate()
        gate.completeFirst(ladder)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(controller.isAvailable)
        XCTAssertFalse(controller.select(.dataSaver))
        XCTAssertEqual(item.preferredPeakBitRate, 0)
    }

    func testChangedCurrentItemAndSourceRequestCannotBorrowOldCapability() async {
        let variants = ladder
        let controller = SinglePlaybackQualityController(loadVariants: { _ in variants })
        let original = item(), replacement = item(), player = AVPlayer()
        player.replaceCurrentItem(with: original)
        let source = UUID(), request = UUID()
        controller.inspect(player: player, item: original, sourceID: source, requestID: request, isCurrent: { true })
        defer { controller.invalidate(); player.replaceCurrentItem(with: nil) }
        await waitFor { controller.isAvailable }
        XCTAssertFalse(controller.matches(player: player, item: original, sourceID: UUID(), requestID: request))
        XCTAssertFalse(controller.matches(player: player, item: original, sourceID: source, requestID: UUID()))
        player.replaceCurrentItem(with: replacement)
        XCTAssertFalse(controller.select(.dataSaver))
        XCTAssertEqual(replacement.preferredPeakBitRate, 0)
        XCTAssertEqual(original.preferredPeakBitRate, 0)
    }

    func testSingleModeQualityPreservesPausedItemAttemptAndNativeFullscreenOrPiP() async throws {
        for pip in [false, true] {
            let variants = ladder
            let controller = SinglePlaybackQualityController(loadVariants: { _ in variants })
            let model = model(controller: controller)
            defer { model.cleanup() }
            let item = item(), player = AVPlayer()
            player.replaceCurrentItem(with: item)
            model.player = player
            model.transition(to: .playing(.native), phase: "Playing")
            model.togglePlayPause()
            model.isVideoReadyForDisplay = true
            model.isPictureInPictureActive = pip
            if !pip { model.beginNativeFullscreen() }
            let fullscreen = model.nativeFullscreen, request = model.loadRequestID, source = model.activeSource?.id
            if !pip { XCTAssertNotNil(fullscreen) }
            try confirm(model)
            await waitFor { model.canChooseSinglePlaybackQuality }

            XCTAssertTrue(model.selectSinglePlaybackQuality(.dataSaver))
            XCTAssertTrue(model.selectSinglePlaybackQuality(.auto))

            XCTAssertTrue(model.player === player)
            XCTAssertTrue(player.currentItem === item)
            XCTAssertEqual(model.loadRequestID, request)
            XCTAssertEqual(model.activeSource?.id, source)
            XCTAssertEqual(model.playbackState, .paused(.native))
            XCTAssertFalse(model.userWantsPlayback)
            XCTAssertEqual(player.rate, 0)
            XCTAssertEqual(model.isPictureInPictureActive, pip)
            XCTAssertTrue(model.nativeFullscreen === fullscreen)
            XCTAssertNil(model.loadTask)
            XCTAssertFalse(model.didStartPlayback)
        }
    }

    func testLeavingSingleRestoresOriginalItemBeforePairedReuseAndLateInspectionCannotLeak() async throws {
        let variants = ladder
        let controller = SinglePlaybackQualityController(loadVariants: { _ in variants })
        let model = model(controller: controller)
        defer { model.cleanup() }
        let item = item(), player = AVPlayer()
        item.preferredPeakBitRate = 3_000_000
        player.replaceCurrentItem(with: item)
        model.player = player
        try confirm(model)
        await waitFor { model.canChooseSinglePlaybackQuality }
        XCTAssertTrue(model.selectSinglePlaybackQuality(.dataSaver))
        let request = model.loadRequestID

        model.setViewingPlaybackContext(.watchTwo(engine: .native))

        XCTAssertEqual(item.preferredPeakBitRate, 3_000_000, "Restore synchronously before a retained item enters paired mode")
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        XCTAssertEqual(controller.preference, .auto)
        XCTAssertFalse(model.canChooseSinglePlaybackQuality)
        XCTAssertFalse(model.selectSinglePlaybackQuality(.dataSaver))
        XCTAssertTrue(model.player === player)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(model.loadRequestID, request)
        XCTAssertNil(model.loadTask)
    }

    func testPairInitializerAndWebListedHDNeverInspectOrExposeNativeQuality() async throws {
        for web in [false, true] {
            var calls = 0
            let variants = ladder
            let controller = SinglePlaybackQualityController(loadVariants: { _ in calls += 1; return variants })
            let model = model(controller: controller, web: web, configureSingle: web)
            defer { model.cleanup() }
            let item = item()
            model.player = AVPlayer(playerItem: item)
            try confirm(model)
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(calls, 0)
            XCTAssertFalse(model.canChooseSinglePlaybackQuality)
            XCTAssertFalse(model.selectSinglePlaybackQuality(.dataSaver))
            XCTAssertEqual(item.preferredPeakBitRate, 0)
            XCTAssertNil(model.loadTask)
        }
    }

    func testSourceSelectionInvalidatesQualityBeforeOldDecodedCallbackCanReapply() async throws {
        let variants = ladder
        let controller = SinglePlaybackQualityController(loadVariants: { _ in variants })
        let model = model(controller: controller, alternatives: true)
        defer { model.cleanup() }
        let item = item()
        model.player = AVPlayer(playerItem: item)
        try confirm(model)
        await waitFor { model.canChooseSinglePlaybackQuality }
        XCTAssertTrue(model.selectSinglePlaybackQuality(.dataSaver))
        let oldSource = try XCTUnwrap(model.activeSource), request = model.loadRequestID
        model.currentSourceIndex = (model.currentSourceIndex + 1) % model.sessions.count
        model.recordPlaybackStage(.decoded, sourceID: oldSource.id, requestID: request)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertFalse(model.canChooseSinglePlaybackQuality)
        XCTAssertEqual(controller.preference, .auto)
        XCTAssertNil(model.loadTask)
    }

    func testRetiredModelRejectsLateVariantResultAndPreservesUnmodifiedOriginalPreferences() async throws {
        let gate = VariantGate()
        let controller = SinglePlaybackQualityController(loadVariants: { _ in await gate.load() })
        let model = model(controller: controller)
        defer { gate.finishAll(); model.cleanup() }
        let item = item()
        model.player = AVPlayer(playerItem: item)
        try confirm(model)
        await waitFor { gate.pending.count == 1 }
        model.cleanup()
        gate.completeFirst(ladder)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(controller.isAvailable)
        XCTAssertFalse(model.canChooseSinglePlaybackQuality)
        XCTAssertFalse(model.selectSinglePlaybackQuality(.dataSaver))
        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        XCTAssertTrue(model.isPlaybackSessionRetired)
    }

    func testLateVariantResultRequiresTheOriginalCurrentOwnerEvenWithoutExplicitInvalidation() async {
        let gate = VariantGate()
        let controller = SinglePlaybackQualityController(loadVariants: { _ in await gate.load() })
        let item = item(), player = AVPlayer()
        player.replaceCurrentItem(with: item)
        var currentOwner = true
        controller.inspect(player: player, item: item, sourceID: UUID(), requestID: UUID(), isCurrent: { currentOwner })
        defer { gate.finishAll(); controller.invalidate(); player.replaceCurrentItem(with: nil) }
        await waitFor { gate.pending.count == 1 }
        currentOwner = false
        gate.completeFirst(ladder)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(controller.isAvailable)
        XCTAssertFalse(controller.select(.dataSaver))
        XCTAssertEqual(item.preferredPeakBitRate, 0)
    }

    private final class VariantGate {
        var pending: [CheckedContinuation<[Variant], Never>] = []
        func load() async -> [Variant] { await withCheckedContinuation { pending.append($0) } }
        func completeFirst(_ values: [Variant]) {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume(returning: values)
        }
        func finishAll() { while !pending.isEmpty { completeFirst([]) } }
    }
}

private final class ReadyQualityItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}
