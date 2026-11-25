import Foundation
import XCTest
import UIKit

@testable import Fotty

@MainActor
final class WebEmbedToolbarLayoutTests: XCTestCase {
    private func layout(fontSize: CGFloat = 13, width: CGFloat? = nil,
                        showSources: Bool = true) -> WebEmbedToolbarView.ToolbarView {
        let toolbar = WebEmbedToolbarView.ToolbarView()
        toolbar.update(isPlaying: true, showSources: showSources, fontSize: fontSize)
        toolbar.frame = CGRect(origin: .zero, size: toolbar.fittingSize(maximumWidth: width))
        toolbar.layoutIfNeeded()
        return toolbar
    }

    private func assertReadable(_ button: UIButton, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(button.bounds.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.bounds.width + 1, button.intrinsicContentSize.width,
                                   "The full configured label and symbol must fit", file: file, line: line)
    }

    func testSourcesMeasuresFullLabelRatherThanSharingTheOldFixedFrame() {
        let toolbar = layout()
        XCTAssertEqual(toolbar.sourcesButton.configuration?.title, "Sources")
        assertReadable(toolbar.pauseButton)
        assertReadable(toolbar.sourcesButton)
        XCTAssertEqual(toolbar.pauseButton.frame.minY, toolbar.sourcesButton.frame.minY, accuracy: 1)
        XCTAssertGreaterThan(toolbar.sourcesButton.frame.minX, toolbar.pauseButton.frame.minX)
    }

    func testNarrowToolbarReflowsWithoutShrinkingOrSplittingTheLabel() {
        let toolbar = layout(width: 120)
        assertReadable(toolbar.pauseButton)
        assertReadable(toolbar.sourcesButton)
        XCTAssertGreaterThan(toolbar.sourcesButton.frame.minY, toolbar.pauseButton.frame.maxY)
        XCTAssertLessThanOrEqual(toolbar.bounds.width, 120)
    }

    func testLargerTextGrowsButtonsAndReflowsWhenNeeded() {
        let ordinary = layout()
        let accessible = layout(fontSize: 28, width: 240)
        assertReadable(accessible.pauseButton)
        assertReadable(accessible.sourcesButton)
        XCTAssertGreaterThan(accessible.sourcesButton.bounds.width, ordinary.sourcesButton.bounds.width)
        XCTAssertGreaterThan(accessible.sourcesButton.frame.minY, accessible.pauseButton.frame.maxY)
        XCTAssertLessThanOrEqual(accessible.bounds.width, 240)
    }

    func testHidingSourcesAndReturningToWideLayoutDoesNotRetainEmptySpace() {
        let toolbar = layout(width: 120)
        toolbar.frame.size = toolbar.fittingSize(maximumWidth: 600)
        toolbar.layoutIfNeeded()
        XCTAssertEqual(toolbar.pauseButton.frame.minY, toolbar.sourcesButton.frame.minY, accuracy: 1)
        let twoButtonWidth = toolbar.bounds.width
        toolbar.update(isPlaying: false, showSources: false)
        toolbar.frame.size = toolbar.fittingSize(maximumWidth: 600)
        toolbar.layoutIfNeeded()
        XCTAssertTrue(toolbar.sourcesButton.isHidden)
        XCTAssertEqual(toolbar.pauseButton.configuration?.title, "Play")
        assertReadable(toolbar.pauseButton)
        XCTAssertLessThan(toolbar.bounds.width, twoButtonWidth)
    }
}

/// Source and bundle contracts for the Apple-platform baseline. These tests do
/// not replace App Review or physical acceptance; they keep sensitive platform
/// decisions visible when unrelated feature work changes the project.
final class ApplePlatformBaselineTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }

    private func propertyList(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func captures(_ pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges == 2,
                  let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    func testATSAndPrivacyDeclarationsRemainExplicitAndReviewable() throws {
        let info = try propertyList("Fotty/Info.plist")
        let ats = try XCTUnwrap(info["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(ats["NSAllowsArbitraryLoads"] as? Bool, false)
        XCTAssertEqual(ats["NSAllowsArbitraryLoadsInWebContent"] as? Bool, false)

        let privacy = try propertyList("Fotty/Resources/PrivacyInfo.xcprivacy")
        XCTAssertEqual(privacy["NSPrivacyTracking"] as? Bool, false)
        XCTAssertNotNil(privacy["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertNotNil(privacy["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        let baseline = try source("docs/APPLE-PLATFORM-BASELINE.md")
        XCTAssertTrue(baseline.contains("NSAllowsArbitraryLoadsInWebContent = NO"))
        XCTAssertTrue(baseline.contains("reviewed HTTPS origins"))
        XCTAssertTrue(baseline.contains("Generate an archive privacy report"))
    }

    func testWebKitAndAudioBoundariesMatchTheMediaPlaybackPolicy() throws {
        let webEmbed = try source("Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift")
        XCTAssertTrue(webEmbed.contains("configuration.allowsInlineMediaPlayback = true"))
        XCTAssertTrue(webEmbed.contains("configuration.allowsPictureInPictureMediaPlayback = true"))
        XCTAssertTrue(webEmbed.contains("configuration.mediaTypesRequiringUserActionForPlayback = []"))

        let app = try source("Fotty/App/FottyApp.swift")
        XCTAssertFalse(app.contains("MediaAudioSession.activateForPlaybackIfNeeded()"),
                       "The app shell must not activate audio before playback begins")

        let audioOwner = try source("Fotty/Core/Media/MediaAudioSessionOwner.swift")
        XCTAssertTrue(audioOwner.contains("func activateForPlaybackIfNeeded() async"))
        XCTAssertTrue(audioOwner.contains("DispatchQueue(label: \"com.jelani.Fotty.audio-session\""))
        let player = try source("Fotty/Features/Player/LivePlayerViewModel.swift")
        XCTAssertTrue(player.contains("await MediaAudioSession.activateForPlaybackIfNeeded()"))
        XCTAssertTrue(player.contains("await MediaAudioPlaybackGate.prepare"))
        XCTAssertTrue(audioOwner.contains("audiovisualBackgroundPlaybackPolicy = .continuesIfPossible"))
        XCTAssertTrue(audioOwner.contains("canUseNetworkResourcesForLiveStreamingWhilePaused = true"))
        let nativePreparation = try source("Fotty/Features/Player/NativePlaybackPreparation.swift")
        XCTAssertTrue(player.contains("NativePlaybackPreparation.makeItem("),
                      "The player must use the shared native item preparation policy")
        XCTAssertTrue(nativePreparation.contains("configureNativeLivePlaybackItem(item)"))
        XCTAssertTrue(webEmbed.contains("await MediaAudioSession.configureForPlayback()"))
        XCTAssertTrue(webEmbed.contains("loadingGeneration == generation"))
        let multi = try source("Fotty/Features/Player/MultiLivePlayerView.swift")
        XCTAssertTrue(multi.contains("await MediaAudioPlaybackGate.prepareNative"))
        XCTAssertTrue(multi.contains("expected: identity, currentIdentity: { audioPlaybackIdentity }"))
        XCTAssertTrue(multi.contains("playbackMayStart: { playbackMayStart && error == nil }"))
        XCTAssertTrue(multi.contains("cancelAudioPreparation()\n        finishObservedStall(.failed)\n        player?.pause()\n        stallValidationTask?.cancel()\n        foregroundResumeValidationTask?.cancel()\n        webRetryOwner.cancel()\n        stopPlaybackWatchdog()\n        failedSourceIDs.insert(failedSource.id)"),
                      "Source exhaustion must revoke pending audio before publishing a terminal failure")
    }

    func testMultiViewRotationPreservesPlayerIdentity() throws {
        let multiView = try source("Fotty/Features/Player/MultiLivePlayerView.swift")
        XCTAssertTrue(multiView.contains("let adaptiveLayout: AnyLayout"))
        XCTAssertTrue(multiView.contains("AnyLayout(HStackLayout(spacing: 8))"))
        XCTAssertTrue(multiView.contains("AnyLayout(VStackLayout(spacing: 8))"))
        XCTAssertFalse(
            multiView.contains("if isLandscape {\n                            HStack"),
            "Switching container branches recreates both WKWebViews and loses playback during rotation"
        )
    }

    func testWebDocumentsAreIsolatedByAttemptInBothPlaybackSurfaces() throws {
        for path in ["Fotty/Features/Player/LivePlayerView.swift",
                     "Fotty/Features/Player/MultiLivePlayerView.swift"] {
            let player = try source(path)
            XCTAssertTrue(player.contains("let attemptID = " + (path.contains("MultiLive") ? "loadRequestID" : "viewModel.loadRequestID")))
            XCTAssertTrue(player.contains(".id(attemptID)"),
                          "An old provider document must not share a WebView with a new source/retry")
        }
    }

    func testMultiViewKeepsPerPanelSourceAndAudioControlsVisible() throws {
        let multiView = try source("Fotty/Features/Player/MultiLivePlayerView.swift")
        XCTAssertTrue(multiView.contains("Text(\"Source \\(currentSourceIndex + 1)\")"))
        XCTAssertTrue(multiView.contains("Changes only the stream in panel"))
        XCTAssertTrue(multiView.contains("Switches audio to this panel"))
        XCTAssertTrue(multiView.contains("panelHeader(layout: chromeLayout)"),
                      "Every panel must render its persistent adaptive control header")
        XCTAssertTrue(multiView.contains("private func panelHeader(layout: MultiLivePanelChromeLayout)"))
        XCTAssertTrue(multiView.contains("private var sourceMenu: some View"))
        XCTAssertTrue(multiView.contains("private var audioButton: some View"))
        XCTAssertTrue(multiView.contains(".frame(width: geometry.size.width)"),
                      "Controls must use the allocated panel width, not a compressed fitted-video width")
        XCTAssertTrue(multiView.contains("multiview-video-surface-"))
        XCTAssertTrue(multiView.contains("layoutMode: MultiViewLayoutMode = .focus"))
        XCTAssertTrue(multiView.contains("isFillMode = false"))
        XCTAssertFalse(
            multiView.contains("if showControls"),
            "Per-panel source selection must not disappear behind auto-hidden playback chrome"
        )
    }

    func testAppAndExtensionReleaseIdentityCannotDrift() throws {
        let project = try source("Fotty.xcodeproj/project.pbxproj")
        let config = try source("project.yml")
        let projectVersions = try captures(#"MARKETING_VERSION = ([^;]+);"#, in: project)
        let projectBuilds = try captures(#"CURRENT_PROJECT_VERSION = ([^;]+);"#, in: project)
        let configVersions = try captures(#"MARKETING_VERSION: ([^\s]+)"#, in: config)
        let configBuilds = try captures(#"CURRENT_PROJECT_VERSION: ([^\s]+)"#, in: config)

        XCTAssertFalse(projectVersions.isEmpty)
        XCTAssertFalse(projectBuilds.isEmpty)
        XCTAssertEqual(projectVersions.count, 4, "Two targets × Debug/Release must each declare a marketing version")
        XCTAssertEqual(projectBuilds.count, 4, "Two targets × Debug/Release must each declare a build number")
        XCTAssertEqual(configVersions.count, 2, "project.yml must declare both app and extension versions")
        XCTAssertEqual(configBuilds.count, 2, "project.yml must declare both app and extension build numbers")
        XCTAssertEqual(Set(projectVersions).count, 1, "Every Xcode target must share one marketing version")
        XCTAssertEqual(Set(projectBuilds).count, 1, "Every Xcode target must share one build number")
        XCTAssertEqual(Set(configVersions), Set(projectVersions))
        XCTAssertEqual(Set(configBuilds), Set(projectBuilds))

        for plistPath in ["Fotty/Info.plist", "FottyLiveActivityExtension/Info.plist"] {
            let plist = try propertyList(plistPath)
            XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
            XCTAssertEqual(plist["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")
        }
    }

    func testBaselineReferencesCurrentAppleGuidanceAndKnownOpenGates() throws {
        let baseline = try source("docs/APPLE-PLATFORM-BASELINE.md")
        for required in [
            "Understanding and improving SwiftUI performance",
            "Migrating from `ObservableObject` to the Observation macro",
            "Adopting strict concurrency in Swift 6",
            "Configuring your app for media playback",
            "Privacy manifest files",
            "Asking permission to use notifications",
            "Writing and running performance tests"
        ] {
            XCTAssertTrue(baseline.contains(required), "Baseline is missing: \(required)")
        }
        XCTAssertTrue(baseline.contains("| Swift concurrency | Open |"))
        XCTAssertTrue(baseline.contains("| Transport security / ATS | Implemented |"))
        XCTAssertTrue(baseline.contains("| Privacy manifest | Amber |"))
    }

    func testDistributionWorkflowRequiresImmutableSourceReceipt() throws {
        let workflow = try source("docs/notebooklm/Workflow.md")
        XCTAssertTrue(workflow.contains("release_source_snapshot.py capture"))
        XCTAssertTrue(workflow.contains("--purpose pre-build"))
        XCTAssertTrue(workflow.contains("release_source_snapshot.py compare"))
        XCTAssertTrue(workflow.contains("receipt.json"))
    }
}

/// Exercise the actual refresh merge and streaming body collector. Tiny byte
/// limits make the boundary deterministic without large image fixtures/network.
@MainActor
final class BadgeResourceSafetyTests: XCTestCase {
    func testCachedFallbackCannotSkipViableHigherPriorityArtwork() async throws {
        let primary = URL(string: "https://badges.invalid/official.png")!
        let fallback = URL(string: "https://badges.invalid/unrelated-warm-fallback.png")!
        let cache = [fallback: "wrong warm fallback"]
        var requested: [URL] = []
        XCTAssertNil(FottyImageSelectionPolicy.preferredCached(urls: [primary, fallback]) { cache[$0] },
            "Do not synchronously show a lower-priority cached image before the primary is tried")
        let result = await FottyImageSelectionPolicy.load(urls: [primary, fallback], cache: { cache[$0] }) { url in
            requested.append(url)
            return "correct official artwork"
        }
        XCTAssertEqual(requested, [primary])
        XCTAssertEqual(result?.selectedURL, primary)
        XCTAssertEqual(result?.value, "correct official artwork")
    }

    func testFailedPrimaryMayUseCachedFallbackWithoutDuplicateDownload() async throws {
        let primary = URL(string: "https://badges.invalid/failed.png")!
        let fallback = URL(string: "https://badges.invalid/accepted-fallback.png")!
        let cache = [fallback: "accepted fallback"]
        var requested: [URL] = []
        let result = await FottyImageSelectionPolicy.load(urls: [primary, primary, fallback], cache: { cache[$0] }) { url in
            requested.append(url)
            return nil as String?
        }
        XCTAssertEqual(requested, [primary], "One failed candidate is not downloaded twice; a warm fallback requires no download")
        XCTAssertEqual(result?.selectedURL, fallback)
        XCTAssertEqual(result?.value, "accepted fallback")
    }

    func testLoadedArtworkBelongsToTheCompleteCurrentCandidateList() async throws {
        let first = URL(string: "https://badges.invalid/first-team.png")!
        let second = URL(string: "https://badges.invalid/second-team.png")!
        let fallback = URL(string: "https://badges.invalid/fallback.png")!
        let result = await FottyImageSelectionPolicy.load(urls: [first, fallback], cache: { _ in nil as String? }) { _ in "first team" }
        XCTAssertEqual(result?.value(for: [first, fallback]), "first team")
        XCTAssertNil(result?.value(for: [second, fallback]), "Reused view state must not display the previous team's artwork")
        XCTAssertNil(result?.value(for: [fallback, first]), "Changed candidate priority invalidates the previous load too")
        XCTAssertNil(result?.value(for: []))
    }

    func testCancelledArtworkLoadCannotPublishOrFallThrough() async {
        let primary = URL(string: "https://badges.invalid/late.png")!
        let fallback = URL(string: "https://badges.invalid/fallback.png")!
        var requested: [URL] = []
        let task = Task { @MainActor in
            await FottyImageSelectionPolicy.load(urls: [primary, fallback], cache: { _ in nil as String? }) { url in
                requested.append(url)
                withUnsafeCurrentTask { $0?.cancel() }
                return "obsolete artwork"
            }
        }
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(requested, [primary])
    }

    private func response(status: Int = 200, length: Int? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://badges.invalid/test.png")!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: length.map { ["Content-Length": String($0)] })!
    }

    func testKnownOversizeHeaderIsRejectedBeforeReadingBody() async {
        let bytes = CountedBadgeBytes([1, 2, 3, 4])
        do {
            _ = try await FottyBoundedImageDownload.collect(bytes, response: response(length: 4), maximumBytes: 3)
            XCTFail("Oversized headers must fail before body accumulation")
        } catch {
            XCTAssertEqual(error as? FottyBoundedImageDownload.Failure, .responseTooLarge)
        }
        XCTAssertEqual(bytes.counter.count, 0)
    }

    func testUnknownLengthStopsBeforeAccumulationExceedsLimit() async {
        let bytes = CountedBadgeBytes(Array(repeating: 7, count: 100))
        do {
            _ = try await FottyBoundedImageDownload.collect(bytes, response: response(), maximumBytes: 3)
            XCTFail("Chunked responses are bounded too")
        } catch {
            XCTAssertEqual(error as? FottyBoundedImageDownload.Failure, .responseTooLarge)
        }
        XCTAssertEqual(bytes.counter.count, 4, "Only one overflow byte is inspected; the remainder is never consumed")
    }

    func testIncorrectSmallHeaderCannotBypassActualByteLimit() async {
        let bytes = CountedBadgeBytes([1, 2, 3, 4, 5])
        do {
            _ = try await FottyBoundedImageDownload.collect(bytes, response: response(length: 1), maximumBytes: 3)
            XCTFail("Content-Length is not the body authority")
        } catch {
            XCTAssertEqual(error as? FottyBoundedImageDownload.Failure, .responseTooLarge)
        }
        XCTAssertEqual(bytes.counter.count, 4)
    }

    func testExactLimitAndEmptyBodiesCompleteNormally() async throws {
        let accepted = try await FottyBoundedImageDownload.collect(
            CountedBadgeBytes([1, 2, 3]), response: response(length: 3), maximumBytes: 3)
        XCTAssertEqual(accepted, Data([1, 2, 3]))
        let empty = try await FottyBoundedImageDownload.collect(
            CountedBadgeBytes([]), response: response(length: 0), maximumBytes: 3)
        XCTAssertEqual(empty, Data())
    }

    func testHTTPFailureIsRejectedBeforeReadingBody() async {
        let bytes = CountedBadgeBytes([1, 2, 3])
        do {
            _ = try await FottyBoundedImageDownload.collect(bytes, response: response(status: 503), maximumBytes: 3)
            XCTFail("Failed responses never enter decoding")
        } catch {
            XCTAssertEqual(error as? FottyBoundedImageDownload.Failure, .invalidResponse)
        }
        XCTAssertEqual(bytes.counter.count, 0)
    }

    func testCancelledCollectorDoesNotReadOrReturnPartialImage() async {
        let bytes = CountedBadgeBytes([1, 2, 3])
        let http = response()
        let task = Task { try await FottyBoundedImageDownload.collect(bytes, response: http, maximumBytes: 3) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must abort collection") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(bytes.counter.count, 0)
    }

    func testOversizeHeaderCancelsTheActualSessionTask() async {
        let stopped = expectation(description: "Rejected transport cancelled")
        HeaderOnlyBadgeProtocol.configure(length: 4, onStart: {}, onStop: { stopped.fulfill() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeaderOnlyBadgeProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); HeaderOnlyBadgeProtocol.reset() }
        var deadlineFired = false
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            deadlineFired = true
            session.invalidateAndCancel()
        }
        defer { deadline.cancel() }
        do {
            _ = try await FottyBoundedImageDownload.data(
                for: URLRequest(url: URL(string: "https://badges.invalid/header.png")!),
                session: session, maximumBytes: 3)
            XCTFail("Oversized response must be rejected without waiting for its body")
        } catch {
            XCTAssertEqual(error as? FottyBoundedImageDownload.Failure, .responseTooLarge)
        }
        deadline.cancel()
        XCTAssertFalse(deadlineFired, "Oversized headers must fail without waiting for the test deadline")
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertFalse(deadlineFired, "The test deadline must not supply transport cancellation")
    }

    func testCallerCancellationStopsHeaderOnlyTransport() async {
        let started = expectation(description: "Headers received")
        let stopped = expectation(description: "Header-only transport cancelled")
        HeaderOnlyBadgeProtocol.configure(length: nil, onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeaderOnlyBadgeProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); HeaderOnlyBadgeProtocol.reset() }
        var deadlineFired = false
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            deadlineFired = true
            session.invalidateAndCancel()
        }
        defer { deadline.cancel() }
        let task = Task {
            try await FottyBoundedImageDownload.data(
                for: URLRequest(url: URL(string: "https://badges.invalid/wait.png")!),
                session: session, maximumBytes: 3)
        }
        await fulfillment(of: [started], timeout: 2)
        // This exercises cancellation of a real header-only URLSession request;
        // scheduling may cancel before or after the collector starts. The
        // deterministic collector cancellation test above covers its own fence.
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transport must not return image data") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        deadline.cancel()
        XCTAssertFalse(deadlineFired, "Caller cancellation must not depend on the test deadline")
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertFalse(deadlineFired, "The test deadline must not supply transport cancellation")
    }

    func testRefreshReplacesOldRemoteURLButKeepsIntentionalArtwork() {
        let old = URL(string: "https://badges.invalid/old.png")!
        let fresh = URL(string: "https://badges.invalid/fresh.png")!
        let protected = URL(string: "https://badges.invalid/protected.png")!
        let result = TeamBrandService.refreshedBadgeCache(
            existing: ["remote team": old, "protected team": old, "quiet team": old],
            publishers: [["remote team": fresh, "protected team": fresh]],
            protected: ["protected team": protected])
        XCTAssertEqual(result["remote team"], fresh)
        XCTAssertEqual(result["protected team"], protected)
        XCTAssertEqual(result["quiet team"], old, "A missing league does not erase accepted branding")
    }

    func testPublisherPriorityIsDeterministicAndInvalidURLsDoNotBlockFallback() {
        let first = URL(string: "https://badges.invalid/first.png")!
        let second = URL(string: "https://badges.invalid/second.png")!
        let result = TeamBrandService.refreshedBadgeCache(existing: [:], publishers: [
            ["team": first, "invalid": URL(string: "file:///private/test.png")!],
            ["team": second, "invalid": second]
        ], protected: [:])
        XCTAssertEqual(result["team"], first)
        XCTAssertEqual(result["invalid"], second)
        XCTAssertEqual(TeamBrandService.refreshedBadgeCache(existing: result, publishers: [[:]], protected: [:]), result)
    }

    func testInvalidPublisherURLsDoNotCountAsSuccessfulRefresh() {
        let invalid = ["relative": URL(string: "relative.png")!, "local": URL(string: "file:///private/test.png")!]
        XCTAssertTrue(TeamBrandService.validatedBadgeEntries(invalid).isEmpty)
        let valid = URL(string: "https://badges.invalid/valid.png")!
        XCTAssertEqual(TeamBrandService.validatedBadgeEntries(invalid.merging(["valid": valid]) { a, _ in a }), ["valid": valid])
    }
}

private struct CountedBadgeBytes: AsyncSequence, Sendable {
    typealias Element = UInt8
    let values: [UInt8]
    let counter = BadgeByteReadCounter()
    init(_ values: [UInt8]) { self.values = values }
    struct AsyncIterator: AsyncIteratorProtocol {
        let values: [UInt8]
        let counter: BadgeByteReadCounter
        var index = 0
        mutating func next() async -> UInt8? {
            guard index < values.count else { return nil }
            let byte = values[index]
            index += 1
            counter.increment()
            return byte
        }
    }
    func makeAsyncIterator() -> AsyncIterator { .init(values: values, counter: counter) }
}

private final class BadgeByteReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

/// An entirely local URLProtocol: sends headers but never a body. Explicit
/// MIME/nosniff metadata makes this controlled fixture observable on the tested
/// Foundation runtime. Success requires cancellation, not fixture completion.
private final class HeaderOnlyBadgeProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var length: Int?
    private static var onStart: (() -> Void)?
    private static var onStop: (() -> Void)?
    static func configure(length: Int?, onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        lock.withLock { self.length = length; self.onStart = onStart; self.onStop = onStop }
    }
    static func reset() { lock.withLock { length = nil; onStart = nil; onStop = nil } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "badges.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (length, callback) = Self.lock.withLock { (Self.length, Self.onStart) }
        var headers = ["Content-Type": "image/png", "X-Content-Type-Options": "nosniff"]
        if let length { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        callback?()
    }
    override func stopLoading() {
        let callback = Self.lock.withLock { Self.onStop }
        callback?()
    }
}
