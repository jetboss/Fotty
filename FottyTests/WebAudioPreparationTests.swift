import XCTest
import WebKit
import JavaScriptCore
@testable import Fotty

#if !targetEnvironment(simulator)
@MainActor
final class WebAudioPreparationTests: XCTestCase {
    private let url = URL(string: "https://player.example.invalid/embed/current")!

    private func makeOwner(gate: WebAudioPreparationGate,
        onFailure: ((String) -> Void)? = nil) -> (LiveWebEmbedPlayerView.Coordinator, AudioPreparationRecordingWebView) {
        let coordinator = LiveWebEmbedPlayerView.Coordinator(onPlaybackStalled: onFailure,
            configureAudioSession: { await gate.prepare() })
        let webView = AudioPreparationRecordingWebView()
        coordinator.webView = webView
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        return (coordinator, webView)
    }

    private func start(_ coordinator: LiveWebEmbedPlayerView.Coordinator,
        in webView: WKWebView, url: URL? = nil, attempt: UUID = UUID()) throws -> Task<Void, Never> {
        let selected = url ?? self.url
        coordinator.beginLoading(url: selected, referer: "https://referer.example.invalid/", attemptID: attempt)
        coordinator.loadAfterAudioConfiguration(URLRequest(url: selected), in: webView)
        return try XCTUnwrap(coordinator.audioConfigurationTask)
    }

    func testWebNavigationWaitsForConfiguredAudioAndStartsFreshDeadline() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        var failures = 0
        let (coordinator, view) = makeOwner(gate: gate, onFailure: { _ in failures += 1 })
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        XCTAssertTrue(view.requests.isEmpty)
        XCTAssertNil(coordinator.startupFailureTask, "Provider startup time must not include audio preparation")
        // Simulate arbitrarily long preparation without sleeping or spending a
        // provider deadline. Only actual navigation may replace this old time.
        coordinator.loadStartedAt = .distantPast
        let releasedAt = Date()
        gate.complete(0, with: .completed([]))
        await task.value
        XCTAssertEqual(view.requests.map(\.url), [url])
        XCTAssertGreaterThanOrEqual(coordinator.loadStartedAt, releasedAt)
        XCTAssertNotNil(coordinator.startupFailureTask)
        XCTAssertEqual(failures, 0)
        XCTAssertNil(coordinator.audioConfigurationTask)
        XCTAssertEqual(view.scriptsAtLoad.count, 1)
    }

    func testCancelledPreparationDoesNotNavigateOrArmProviderDeadline() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        gate.complete(0, with: .cancelled)
        await task.value
        XCTAssertTrue(view.requests.isEmpty)
        XCTAssertNil(coordinator.startupFailureTask)
    }

    func testNewAttemptRejectsOldPreparationAndOnlyLoadsCurrentRequest() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let old = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        let replacement = URL(string: "https://player.example.invalid/embed/replacement")!
        let currentAttempt = UUID()
        let current = try start(coordinator, in: view, url: replacement, attempt: currentAttempt)
        try await gate.waitForCall(1)
        gate.complete(0, with: .completed([]))
        await old.value
        XCTAssertTrue(view.requests.isEmpty)
        XCTAssertNil(coordinator.startupFailureTask)
        gate.complete(1, with: .completed([]))
        await current.value
        XCTAssertEqual(view.requests.map(\.url), [replacement])
        XCTAssertEqual(coordinator.loadedAttemptID, currentAttempt)
        XCTAssertNotNil(coordinator.startupFailureTask)
    }

    func testDismantleRejectsLatePreparationWithoutResurrectingNavigation() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        LiveWebEmbedPlayerView.dismantleUIView(view, coordinator: coordinator)
        gate.complete(0, with: .completed([]))
        await task.value
        XCTAssertTrue(view.requests.isEmpty)
        XCTAssertNil(coordinator.webView)
        XCTAssertNil(coordinator.startupFailureTask)
        XCTAssertNil(view.navigationDelegate)
        XCTAssertNil(view.uiDelegate)
        XCTAssertEqual(view.retirementEvents, ["pause", "suspend", "close", "stop"])
    }

    func testChangedWebViewOwnerRejectsLatePreparation() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        let replacementView = AudioPreparationRecordingWebView()
        coordinator.webView = replacementView
        gate.complete(0, with: .completed([]))
        await task.value
        XCTAssertTrue(view.requests.isEmpty)
        XCTAssertTrue(replacementView.requests.isEmpty)
        XCTAssertNil(coordinator.startupFailureTask)
    }

    func testPauseDuringPreparationSeedsNewDocumentAndSuppressesAutoplayKick() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        coordinator.playbackCommandWillApply(.init(id: UUID(), shouldPlay: false))
        gate.complete(0, with: .completed([]))
        await task.value
        XCTAssertEqual(view.requests.count, 1)
        XCTAssertNil(coordinator.startupFailureTask)
        let document = try newDocument(from: view)
        execute("timers.filter(t => t.delay === 3500).forEach(t => t.fn()); intervals.forEach(t => t.fn());", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 0,
            "A Pause received against the blank page must still prevent the new document's startup play kick")
        XCTAssertEqual(document.evaluateScript("video.paused")?.toBool(), true)
        execute("window.__fottySetPlaying(true);", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 1)
        XCTAssertEqual(document.evaluateScript("video.paused")?.toBool(), false,
            "The carried pause must not disable a later explicit Play")
    }

    func testBackgroundDuringPreparationSeedsSuspensionAndPreservesForegroundResume() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        coordinator.playbackSuspensionChanged(true)
        gate.complete(0, with: .completed([]))
        await task.value
        XCTAssertNil(coordinator.startupFailureTask)
        let document = try newDocument(from: view)
        execute("timers.filter(t => t.delay === 3500).forEach(t => t.fn()); intervals.forEach(t => t.fn());", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 0)
        XCTAssertEqual(document.evaluateScript("video.paused")?.toBool(), true)
        execute("window.__fottySetPlaybackSuspended(false);", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 1,
            "Foreground resume belongs to the new document, not the earlier blank one")
        XCTAssertEqual(document.evaluateScript("video.paused")?.toBool(), false)
    }

    func testPausedSuspendedBootstrapDoesNotAutoResumeOnForeground() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        coordinator.playbackSuspensionChanged(true)
        coordinator.playbackCommandWillApply(.init(id: UUID(), shouldPlay: false))
        gate.complete(0, with: .completed([]))
        await task.value
        let document = try newDocument(from: view)
        execute("intervals.forEach(t => t.fn()); window.__fottySetPlaybackSuspended(false);", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 0,
            "Foreground cannot undo an explicit Pause accepted while preparation was pending")
        XCTAssertEqual(document.evaluateScript("video.paused")?.toBool(), true)
        execute("window.__fottySetPlaying(true);", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 1)
        XCTAssertEqual(document.evaluateScript("video.paused")?.toBool(), false)
    }

    func testMuteAndContentModeChangesDuringPreparationReachNewDocument() async throws {
        for muted in [false, true] {
            let gate = WebAudioPreparationGate()
            defer { gate.cancelAll() }
            let (coordinator, view) = makeOwner(gate: gate)
            coordinator.lastMuted = !muted
            coordinator.lastFillMode = false
            let task = try start(coordinator, in: view)
            try await gate.waitForCall(0)
            coordinator.lastMuted = muted
            coordinator.lastFillMode = true
            gate.complete(0, with: .completed([]))
            await task.value
            let document = try newDocument(from: view)
            execute("intervals.forEach(t => t.fn());", in: document)
            XCTAssertEqual(document.evaluateScript("video.muted")?.toBool(), muted)
            XCTAssertEqual(document.evaluateScript("video.volume")?.toDouble(), muted ? 0 : 1)
            XCTAssertEqual(document.evaluateScript("video.style.values['object-fit']")?.toString(), "cover")
            coordinator.invalidateLoading()
        }
    }

    func testProviderOwnedAudioRemainsUntouchedAfterDelayedPreparation() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        coordinator.providerControlsAudio = true
        coordinator.lastMuted = true
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        gate.complete(0, with: .completed([]))
        await task.value
        let document = try newDocument(from: view)
        execute("video.muted = false; video.volume = 0.4; intervals.forEach(t => t.fn());", in: document)
        XCTAssertEqual(document.evaluateScript("video.muted")?.toBool(), false)
        XCTAssertEqual(document.evaluateScript("video.volume")?.toDouble(), 0.4,
            "Standard provider controls remain canonical; reseeding must not force MultiView audio policy")
    }

    func testResumeCommandsDuringPreparationCannotStartProviderDeadlineEarly() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        coordinator.playbackCommandWillApply(.init(id: UUID(), shouldPlay: false))
        coordinator.playbackCommandWillApply(.init(id: UUID(), shouldPlay: true))
        XCTAssertNil(coordinator.startupFailureTask)
        coordinator.playbackSuspensionChanged(true)
        coordinator.playbackSuspensionChanged(false)
        XCTAssertNil(coordinator.startupFailureTask)
        XCTAssertTrue(view.requests.isEmpty)
        gate.complete(0, with: .completed([]))
        await task.value
        XCTAssertEqual(view.requests.count, 1)
        XCTAssertNotNil(coordinator.startupFailureTask)
        let document = try newDocument(from: view)
        execute("video.paused = true; timers.filter(t => t.delay === 3500).forEach(t => t.fn());", in: document)
        XCTAssertEqual(document.evaluateScript("video.playCalls")?.toInt32(), 1,
            "Latest Play/foreground intent, not an intermediate Pause/background state, seeds the current document")
    }

    func testWatchTwoAudioOwnershipCanEnterAndLeaveWithoutReloadingProviderDocument() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        coordinator.providerControlsAudio = true
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        gate.complete(0, with: .completed([]))
        await task.value
        let document = try newDocument(from: view)
        execute("video.volume = 0.4; window.__fottySetAudioOwnership(true, true);", in: document)
        XCTAssertEqual(document.evaluateScript("video.muted")?.toBool(), true)
        XCTAssertEqual(document.evaluateScript("video.volume")?.toDouble(), 0)
        execute("window.__fottySetAudioOwnership(true, false);", in: document)
        XCTAssertEqual(document.evaluateScript("video.muted")?.toBool(), false)
        XCTAssertEqual(document.evaluateScript("video.volume")?.toDouble(), 1)
        execute("window.__fottySetAudioOwnership(false, false); video.volume = 0.35; intervals.forEach(t => t.fn());", in: document)
        XCTAssertEqual(document.evaluateScript("video.volume")?.toDouble(), 0.35,
            "Leaving Watch Two restores provider audio control instead of enforcing a permanent volume")
        XCTAssertEqual(view.requests.count, 1, "Audio focus must never navigate or create a new document")
    }

    func testMalformedOrForeignFrameAudioOwnershipCannotMuteCurrentProvider() async throws {
        let gate = WebAudioPreparationGate()
        defer { gate.cancelAll() }
        let (coordinator, view) = makeOwner(gate: gate)
        defer { coordinator.invalidateLoading() }
        coordinator.providerControlsAudio = true
        let task = try start(coordinator, in: view)
        try await gate.waitForCall(0)
        gate.complete(0, with: .completed([]))
        await task.value
        let document = try newDocument(from: view)
        execute("window.__fottySetAudioOwnership('true', true);", in: document)
        execute("(windowListeners.message || []).forEach(fn => fn({source:{}, data:{type:'fotty_audio_ownership',managed:true,muted:true}}));", in: document)
        XCTAssertEqual(document.evaluateScript("video.muted")?.toBool(), false)
        XCTAssertEqual(document.evaluateScript("video.volume")?.toDouble(), 1)
    }

    /// Execute the exact production WKUserScript captured at navigation in a
    /// bounded browser/media fake. This proves delayed command behavior, not
    /// playback quality or decoding on a physical WebKit provider.
    private func newDocument(from view: AudioPreparationRecordingWebView) throws -> JSContext {
        let script = try XCTUnwrap(view.scriptsAtLoad.first?.first)
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)
        let context = try XCTUnwrap(JSContext())
        execute(#"""
        var window = this; window.top = window; window.parent = window;
        window.innerWidth = 320; window.innerHeight = 180;
        window.getComputedStyle = node => node.style || {display:'block',visibility:'visible',opacity:'1'};
        var clock = 1000; Date.now = () => clock;
        var messages = [], listeners = {}, timers = [], intervals = [];
        var location = {href:'https://player.example.invalid/embed/current'};
        var navigator = {userAgent:'test'};
        function URL(value) { this.href = value; }
        window.webkit = {messageHandlers:{fottyPlayerBridge:{postMessage:m => messages.push(m)}}};
        var windowListeners = {};
        window.addEventListener = (type, fn) => (windowListeners[type] ||= []).push(fn);
        var performance = {getEntriesByType:() => []};
        function emit(type, target) { (listeners[type] || []).forEach(l => l.fn({target:target})); }
        var video = {
            paused:false, ended:false, currentTime:1, currentSrc:'', readyState:4,
            muted:false, defaultMuted:false, volume:1, playCalls:0,
            videoWidth:320, videoHeight:180, tagName:'VIDEO', isConnected:true, nodeType:1,
            style:{values:{},setProperty:function(name,value){this.values[name]=value;}},
            getBoundingClientRect:()=>({left:0,top:0,right:320,bottom:180,width:320,height:180}),
            closest:()=>null, setAttribute:function(){}, getAttribute:()=>null, querySelectorAll:()=>[],
            pause:function(){this.paused=true; emit('pause', this);},
            play:function(){
                this.playCalls++; this.paused=false; emit('playing', this);
                return {then:(ok) => ok(), catch:function(){}};
            }
        };
        var frames = [];
        var document = {
            hidden:false, body:{innerText:''}, documentElement:{},
            querySelectorAll:s => s === 'iframe' ? frames : s === 'video' || s === 'video, audio' ? [video] : [],
            querySelector:()=>null,
            addEventListener:(t,fn,options) => (listeners[t] ||= []).push({fn,options})
        };
        function MutationObserver(fn) {this.observe=function(){};}
        function setTimeout(fn,delay) {timers.push({fn,delay});}
        function setInterval(fn,delay) {intervals.push({fn,delay});}
        """#, in: context)
        execute(script.source, in: context)
        return context
    }

    private func execute(_ script: String, in context: JSContext,
        file: StaticString = #filePath, line: UInt = #line) {
        context.evaluateScript(script)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Monitor must execute", file: file, line: line)
    }
}

/// Deliberately does not propagate cancellation automatically: the system can
/// complete audio setup after an attempt is replaced, so production must fence
/// that late result itself.
@MainActor
private final class WebAudioPreparationGate {
    private var pending: [CheckedContinuation<MediaAudioSessionPreparation, Never>?] = []
    private var isClosed = false

    private enum GateError: Error { case preparationNotRequested }

    func prepare() async -> MediaAudioSessionPreparation {
        guard !isClosed else { return .cancelled }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
    }

    func waitForCall(_ index: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while pending.count <= index, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard pending.count > index else { throw GateError.preparationNotRequested }
    }

    func complete(_ index: Int, with result: MediaAudioSessionPreparation) {
        let continuation = pending[index]
        pending[index] = nil
        continuation?.resume(returning: result)
    }

    func cancelAll() {
        isClosed = true
        for index in pending.indices { complete(index, with: .cancelled) }
    }
}

/// Records actual production navigation calls and the document-start monitor
/// installed at that moment. It never loads a provider or creates network I/O.
@MainActor
private final class AudioPreparationRecordingWebView: WKWebView {
    private(set) var requests: [URLRequest] = []
    private(set) var scriptsAtLoad: [[WKUserScript]] = []
    private(set) var retirementEvents: [String] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request)
        scriptsAtLoad.append(configuration.userContentController.userScripts)
        return nil
    }

    override func evaluateJavaScript(_ javaScriptString: String,
        completionHandler: (@MainActor (Any?, (any Error)?) -> Void)? = nil) {
        completionHandler?(nil, nil)
    }

    override func pauseAllMediaPlayback(completionHandler: (@MainActor () -> Void)?) {
        retirementEvents.append("pause")
        completionHandler?()
    }

    override func setAllMediaPlaybackSuspended(_ suspended: Bool,
        completionHandler: (@MainActor () -> Void)?) {
        retirementEvents.append("suspend")
        completionHandler?()
    }

    override func closeAllMediaPresentations(completionHandler: (@MainActor () -> Void)?) {
        retirementEvents.append("close")
        completionHandler?()
    }

    override func stopLoading() { retirementEvents.append("stop") }
}
#endif
