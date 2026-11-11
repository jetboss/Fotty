import SwiftUI
import WebKit

#if !targetEnvironment(simulator)
struct LiveWebEmbedPlayerView: UIViewRepresentable {
    let url: URL
    let referer: String
    let isMuted: Bool
    let isSuspended: Bool
    /// The standard player must leave the provider's play, pause, and unmute
    /// controls alone. MultiView opts into Fotty-controlled audio focus.
    var providerControlsAudio = false
    /// Fit is the safe default because sports graphics and scoreboards often sit
    /// at the video edges. MultiView can explicitly opt into a cropped Fill mode.
    var isFillMode = false
    let attemptID: UUID
    var playbackCommand: WebPlaybackCommand? = nil
    /// A reversible, acknowledged interruption for an explicit native transfer.
    /// This is separate from background suspension and destructive retirement.
    var nativeTransferSuspensionID: UUID? = nil
    /// True grants after the current WK acquire ACK. False revokes that grant
    /// immediately; balancing the public false setter completes separately.
    var onNativeTransferSuspensionChanged: (UUID, Bool) -> Void = { _, _ in }
    /// Watch Two waits for the decoded Web owner to confirm managed muting
    /// before another pane may become audible. This never requests Play.
    var webAudioRevocationID: UUID? = nil
    var onWebAudioRevocationAcknowledged: (UUID) -> Void = { _ in }
    var onSurfaceTapped: (() -> Void)? = nil
    var onDiagnosticStage: ((FottyPlaybackStage, Int?) -> Void)? = nil
    var onAudioPreparationMeasured: ((Int, MediaAudioSessionPreparation) -> Void)? = nil
    var onTransportStateChanged: ((WebPlaybackTransportState) -> Void)? = nil
    var onPlaybackStarted: ((Int) -> Void)? = nil
    var onPlaybackStalled: ((String) -> Void)? = nil
    var onPlaybackRecovered: (() -> Void)? = nil
    var onPictureInPictureActiveChanged: ((Bool) -> Void)? = nil
    var onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)? = nil
    /// A native handoff remains muted until WebKit confirms the old media is
    /// paused, including inaccessible child frames. This callback owns the old
    /// attempt only; callers must still fence it against their current attempt.
    var onPlaybackRetired: (() -> Void)? = nil
    var onPlaybackMounted: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSurfaceTapped: onSurfaceTapped,
            onDiagnosticStage: onDiagnosticStage,
            onAudioPreparationMeasured: onAudioPreparationMeasured,
            onTransportStateChanged: onTransportStateChanged,
            onPlaybackStarted: onPlaybackStarted,
            onPlaybackStalled: onPlaybackStalled,
            onPlaybackRecovered: onPlaybackRecovered,
            onPictureInPictureActiveChanged: onPictureInPictureActiveChanged,
            onNativeCandidateDiscovered: onNativeCandidateDiscovered,
            onPlaybackRetired: onPlaybackRetired,
            onNativeTransferSuspensionChanged: onNativeTransferSuspensionChanged,
            onWebAudioRevocationAcknowledged: onWebAudioRevocationAcknowledged
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        MediaAudioSession.configureForPlaybackIfNeeded()

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Provider pages are untrusted and do not need the user's normal Safari
        // cookie/storage state. The ephemeral store still keeps cookies during a
        // single source attempt, which preserves normal player behavior.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "fottyPlayerBridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false

        // Do not arbitrate WebKit's touches with a UIKit recognizer. Even a
        // non-cancelling recognizer delays touch-end by default. A passive DOM
        // observer reveals our controls without consuming provider interaction.
        context.coordinator.webView = webView
        context.coordinator.loadedEmbedURL = url
        context.coordinator.loadedAttemptID = attemptID
        context.coordinator.lastMuted = isMuted
        context.coordinator.lastSuspended = isSuspended
        context.coordinator.lastFillMode = isFillMode
        context.coordinator.lastPlaybackCommandID = playbackCommand?.id
        onPlaybackMounted?()
        load(url: url, referer: referer, attemptID: attemptID, in: webView, coordinator: context.coordinator)
        context.coordinator.lastPlaybackCommandShouldPlay = playbackCommand?.shouldPlay
        context.coordinator.requestNativeTransferSuspension(nativeTransferSuspensionID)
        context.coordinator.requestWebAudioRevocation(webAudioRevocationID)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSurfaceTapped = onSurfaceTapped
        context.coordinator.onDiagnosticStage = onDiagnosticStage
        context.coordinator.onAudioPreparationMeasured = onAudioPreparationMeasured
        context.coordinator.onTransportStateChanged = onTransportStateChanged
        context.coordinator.onPlaybackStarted = onPlaybackStarted
        context.coordinator.onPlaybackStalled = onPlaybackStalled
        context.coordinator.onPlaybackRecovered = onPlaybackRecovered
        context.coordinator.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        context.coordinator.onNativeCandidateDiscovered = onNativeCandidateDiscovered
        context.coordinator.onPlaybackRetired = onPlaybackRetired
        context.coordinator.onNativeTransferSuspensionChanged = onNativeTransferSuspensionChanged
        context.coordinator.onWebAudioRevocationAcknowledged = onWebAudioRevocationAcknowledged

        if context.coordinator.loadedEmbedURL != url
            || context.coordinator.loadedAttemptID != attemptID {
            context.coordinator.loadedEmbedURL = url
            context.coordinator.loadedAttemptID = attemptID
            load(url: url, referer: referer, attemptID: attemptID, in: webView, coordinator: context.coordinator)
        }
        if context.coordinator.providerControlsAudio != providerControlsAudio {
            context.coordinator.providerControlsAudio = providerControlsAudio
            applyAudioOwnershipState(in: webView)
        }
        if context.coordinator.lastMuted != isMuted {
            context.coordinator.lastMuted = isMuted
            applyMutedState(in: webView)
        }
        if context.coordinator.lastSuspended != isSuspended {
            context.coordinator.lastSuspended = isSuspended
            context.coordinator.playbackSuspensionChanged(isSuspended)
            applySuspendedState(in: webView)
        }
        if context.coordinator.lastFillMode != isFillMode {
            context.coordinator.lastFillMode = isFillMode
            applyContentMode(in: webView)
        }
        if let playbackCommand,
           context.coordinator.lastPlaybackCommandID != playbackCommand.id {
            context.coordinator.lastPlaybackCommandID = playbackCommand.id
            context.coordinator.playbackCommandWillApply(playbackCommand)
            applyPlaybackCommand(playbackCommand, in: webView)
        }
        // Observe the latest explicit Pause before deciding whether a released
        // native interruption may restore WebKit's previous playing state.
        context.coordinator.lastPlaybackCommandShouldPlay = playbackCommand?.shouldPlay
        context.coordinator.requestNativeTransferSuspension(nativeTransferSuspensionID)
        context.coordinator.requestWebAudioRevocation(webAudioRevocationID)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        let onPlaybackRetired = coordinator.onPlaybackRetired
        coordinator.onPlaybackRetired = nil
        coordinator.invalidateLoading()
        if coordinator.isPictureInPictureActive {
            coordinator.isPictureInPictureActive = false
            coordinator.onPictureInPictureActiveChanged?(false)
        }
        webView.evaluateJavaScript(teardownScript)
        // The decoded owner may live in an opaque cross-origin child frame or
        // a native WebKit PiP/fullscreen presentation. DOM access alone cannot
        // guarantee that old media stops before the next attempt is installed.
        webView.pauseAllMediaPlayback(completionHandler: nil)
        // Retired pages cannot restart their own timers/media after the pause.
        // This is teardown only, not a change to active provider controls.
        webView.setAllMediaPlaybackSuspended(true) { [webView] in
            // Keep the exact retired surface alive until WebKit acknowledges
            // suspension; removing SwiftUI's owner must not lose that receipt.
            withExtendedLifetime(webView) { onPlaybackRetired?() }
        }
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "fottyPlayerBridge")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.webView = nil
    }

    static var teardownScript: String {
        """
        (function() {
            try {
                if (typeof window.__fottySetPlaybackSuspended === 'function') {
                    window.__fottySetPlaybackSuspended(true);
                }
            } catch (e) {}
            document.querySelectorAll('video, audio').forEach(function(media) {
                try { media.pause(); } catch (e) {}
            });
            document.querySelectorAll('iframe').forEach(function(frame) {
                try {
                    if (frame.contentWindow) {
                        frame.contentWindow.postMessage({type:'fotty_set_suspended', suspended:true}, '*');
                    }
                } catch (e) {}
            });
        })();
        """
    }

    private func load(
        url: URL,
        referer: String,
        attemptID: UUID,
        in webView: WKWebView,
        coordinator: Coordinator
    ) {
        MediaAudioSession.configureForPlaybackIfNeeded()
        if coordinator.isPictureInPictureActive {
            coordinator.isPictureInPictureActive = false
            coordinator.onPictureInPictureActiveChanged?(false)
        }
        coordinator.beginLoading(url: url, referer: referer, attemptID: attemptID)
        coordinator.providerControlsAudio = providerControlsAudio

        Self.configurePlaybackMonitor(
            in: webView.configuration.userContentController,
            url: url,
            isMuted: isMuted,
            providerControlsAudio: providerControlsAudio,
            isSuspended: isSuspended,
            isFillMode: isFillMode,
            attemptID: attemptID
        )
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 15
        if !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        // Leave User-Agent untouched so WKWebView presents its real iPad/iPhone
        // browser identity. A hard-coded desktop UA caused provider divergence.
        coordinator.loadAfterAudioConfiguration(request, in: webView)
    }

    static func configurePlaybackMonitor(
        in controller: WKUserContentController,
        url: URL,
        isMuted: Bool,
        providerControlsAudio: Bool,
        isSuspended: Bool,
        isFillMode: Bool = false,
        attemptID: UUID? = nil,
        isUserPaused: Bool = false
    ) {
        // Native callers isolate each attempt with a fresh representable ID.
        // Still replace rules defensively if another caller reuses a web view,
        // rather than accumulating a previous document's provider-specific rules.
        // This controller is owned by this player; its bridge handler is retained.
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: playbackMonitorScript(
                isMuted: isMuted,
                providerControlsAudio: providerControlsAudio,
                isSuspended: isSuspended,
                isScore808Site: Score808SiteCatalog.safeWatchPageURL(url.absoluteString) != nil,
                isFillMode: isFillMode,
                attemptID: attemptID,
                isUserPaused: isUserPaused
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }

    private func applyAudioOwnershipState(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__fottySetAudioOwnership && window.__fottySetAudioOwnership(\(providerControlsAudio ? "false" : "true"), \(isMuted ? "true" : "false"));")
    }

    private func applyMutedState(in webView: WKWebView) {
        guard !providerControlsAudio else { return }
        let muted = isMuted ? "true" : "false"
        webView.evaluateJavaScript(
            """
            (function() {
                var muted = \(muted);
                try {
                    if (typeof window.__fottySetMuted === 'function') {
                        window.__fottySetMuted(muted);
                    } else {
                        document.querySelectorAll('video, audio').forEach(function(media) {
                            media.muted = muted;
                            media.volume = muted ? 0 : 1;
                        });
                        document.querySelectorAll('iframe').forEach(function(frame) {
                            try {
                                if (frame.contentWindow) {
                                    frame.contentWindow.postMessage({ type: 'fotty_set_muted', muted: muted }, '*');
                                }
                            } catch (e) {}
                        });
                    }
                } catch (e) {}
            })();
            """
        )
    }

    private func applySuspendedState(in webView: WKWebView) {
        let suspended = isSuspended ? "true" : "false"
        webView.evaluateJavaScript(
            """
            (function() {
                try {
                    if (typeof window.__fottySetPlaybackSuspended === 'function') {
                        window.__fottySetPlaybackSuspended(\(suspended));
                    }
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        try {
                            if (frame.contentWindow) {
                                frame.contentWindow.postMessage(
                                    { type: 'fotty_set_suspended', suspended: \(suspended) },
                                    '*'
                                );
                            }
                        } catch (e) {}
                    });
                } catch (e) {}
            })();
            """
        )
    }

    private func applyContentMode(in webView: WKWebView) {
        let fill = isFillMode ? "true" : "false"
        webView.evaluateJavaScript(
            """
            (function() {
                try {
                    if (typeof window.__fottySetContentMode === 'function') {
                        window.__fottySetContentMode(\(fill));
                    }
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        try {
                            if (frame.contentWindow) {
                                frame.contentWindow.postMessage(
                                    { type: 'fotty_set_content_mode', fill: \(fill) },
                                    '*'
                                );
                            }
                        } catch (e) {}
                    });
                } catch (e) {}
            })();
            """
        )
    }

    private func applyPlaybackCommand(_ command: WebPlaybackCommand, in webView: WKWebView) {
        let shouldPlay = command.shouldPlay ? "true" : "false"
        webView.evaluateJavaScript(
            """
            (function() {
                try {
                    if (typeof window.__fottySetPlaying === 'function') {
                        window.__fottySetPlaying(\(shouldPlay));
                    }
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        try {
                            if (frame.contentWindow) {
                                frame.contentWindow.postMessage(
                                    { type: 'fotty_set_playing', shouldPlay: \(shouldPlay) },
                                    '*'
                                );
                            }
                        } catch (e) {}
                    });
                } catch (e) {}
            })();
            """
        )
    }

    static func playbackMonitorScript(
        isMuted: Bool,
        providerControlsAudio: Bool,
        isSuspended: Bool,
        isScore808Site: Bool = false,
        isFillMode: Bool = false,
        attemptID: UUID? = nil,
        isUserPaused: Bool = false
    ) -> String {
        """
        (function() {
            var score808Site = \(isScore808Site ? "true" : "false");
            // The direct site has one observed main-document player. Its ads
            // and calendar frames must never own decoded playback or handoff.
            // Child frames still need popup and pause/background containment;
            // only their authority to report broadcast playback is excluded.
            var canOwnDocument = !score808Site || window === window.top;
            if (window.__fottyPlaybackMonitorInstalled) return;
            window.__fottyPlaybackMonitorInstalled = true;

            var playbackConfirmed = false;
            var playbackAttemptID = '\(attemptID?.uuidString ?? "")';
            var playbackVideo = null;
            var reportedTransportState = null;
            var playbackDocumentID = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
            var failureReported = false;
            var lastProgressAt = Date.now();
            var lastProgressTime = 0;
            var stallNoticeSent = false;
            var shouldMute = \(isMuted ? "true" : "false");
            var providerControlsAudio = \(providerControlsAudio ? "true" : "false");
            var playbackSuspended = \(isSuspended ? "true" : "false");
            var fillVideo = \(isFillMode ? "true" : "false");
            var playbackUserPaused = \(isUserPaused ? "true" : "false");
            var nativeTransferSuspended = false;
            var nativeTransferSuspensionAcknowledged = false;
            var lastTrustedProviderInteractionAt = 0;
            var resumeAfterSuspend = \(isSuspended && !isUserPaused ? "true" : "false");
            var latestNativeCandidate = '';
            var lastReportedNativeCandidate = '';
            var parentFrameEligible = window === window.top;
            var childClaims = new Map();
            var audioRevocationRequest = null;
            var lastOwnershipAnnouncement = 0;

            var nuisanceHosts = [
                'doubleclick', 'googlesyndication', 'adservice', 'adnxs',
                'exoclick', 'popads', 'popcash', 'propellerads', 'onclicka',
                'trafficjunky', 'histats', 'cdn-lab.shop', 'llvpn',
                'ndcertainlywhen.com', 'tanktds.com', 'stuins.com',
                'my.rtmark.net', 'luugy.com'
            ];

            function isNuisanceURL(value) {
                if (!value || typeof value !== 'string') return false;
                var normalized = value.toLowerCase();
                return nuisanceHosts.some(function(host) { return normalized.indexOf(host) !== -1; })
                    || normalized.indexOf('/ad.html') !== -1
                    || normalized.indexOf('/vast') !== -1;
            }

            function isNuisanceSolicitationText(value) {
                if (!value || typeof value !== 'string') return false;
                var normalized = value.toLowerCase().replace(/\\s+/g, ' ').trim();
                var isVPNInstallPrompt = normalized.indexOf('vpn recommended') !== -1
                    && normalized.indexOf('install') !== -1
                    && normalized.indexOf('continue watching') !== -1;
                var isFakeDownloadPrompt = normalized.indexOf('file is ready for download') !== -1
                    && normalized.indexOf('tap to proceed') !== -1;
                return isVPNInstallPrompt || isFakeDownloadPrompt;
            }

            function removeKnownNuisanceSolicitations() {
                try {
                    if (!document.body || typeof document.createTreeWalker !== 'function') return;
                    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                    var matches = [];
                    var textNode;
                    while ((textNode = walker.nextNode())) {
                        var nodeText = (textNode.nodeValue || '').toLowerCase();
                        if (nodeText.indexOf('vpn recommended') === -1
                            && nodeText.indexOf('file is ready for download') === -1) continue;

                        var candidate = textNode.parentElement;
                        var removable = null;
                        while (candidate && candidate !== document.body && candidate !== document.documentElement) {
                            var combinedText = candidate.innerText || candidate.textContent || '';
                            if (!isNuisanceSolicitationText(combinedText)) {
                                candidate = candidate.parentElement;
                                continue;
                            }

                            // Never remove a provider/player ancestor. The
                            // solicitation itself owns only text/buttons.
                            if (candidate.querySelector('video, iframe')) break;
                            var rect = candidate.getBoundingClientRect();
                            if (rect.width >= window.innerWidth * 0.98
                                && rect.height >= window.innerHeight * 0.98) break;
                            removable = candidate;
                            candidate = candidate.parentElement;
                        }
                        if (removable) matches.push(removable);
                    }
                    matches.forEach(function(element) {
                        if (element && element.isConnected) element.remove();
                    });
                } catch (e) {}
            }

            function removeNuisanceElements() {
                var selectors = [
                    'iframe[src*="/ad.html"]',
                    'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]',
                    'iframe[src*="adservice"]', 'iframe[src*="exoclick"]',
                    'iframe[src*="popads"]', 'iframe[src*="onclicka"]',
                    'iframe[src*="ndcertainlywhen.com"]', 'iframe[src*="tanktds.com"]',
                    'iframe[src*="stuins.com"]', 'iframe[src*="my.rtmark.net"]',
                    'iframe[src*="luugy.com"]',
                    '[id^="google_ads"]', '.adsbygoogle', '[data-ad-slot]',
                    '[class*="popup-ad"]', '[id*="popup-ad"]',
                    '[class*="advertisement"]', '[id*="advertisement"]',
                    '[aria-label*="advertisement" i]'
                ];
                try {
                    document.querySelectorAll(selectors.join(',')).forEach(function(element) {
                        element.remove();
                    });
                } catch (e) {}
                removeKnownNuisanceSolicitations();
            }

            // Reject only reproduced provider solicitations when they are
            // rendered through JavaScript alert/confirm instead of HTML.
            try {
                var originalAlert = window.alert && window.alert.bind(window);
                if (originalAlert) {
                    window.alert = function(message) {
                        if (isNuisanceSolicitationText(String(message || ''))) return;
                        return originalAlert(message);
                    };
                }
                var originalConfirm = window.confirm && window.confirm.bind(window);
                if (originalConfirm) {
                    window.confirm = function(message) {
                        if (isNuisanceSolicitationText(String(message || ''))) return false;
                        return originalConfirm(message);
                    };
                }
            } catch (e) {}

            // The embedded video does not need a second browsing window.
            // Providers use window.open here exclusively for ad click-throughs.
            try {
                Object.defineProperty(window, 'open', {
                    value: function() { return null; },
                    writable: false,
                    configurable: false
                });
            } catch (e) {
                try { window.open = function() { return null; }; } catch (ignored) {}
            }

            function sendMediaMessage(message) {
                try {
                    // Forwarded child messages retain their original attempt.
                    // Never relabel a queued old-document event as the new load.
                    if (!message.attemptID) message.attemptID = playbackAttemptID;
                    if (window !== window.top) {
                        window.parent.postMessage({type:'fotty_media_event', message:message}, '*');
                    } else {
                        var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.fottyPlayerBridge;
                        if (bridge) bridge.postMessage(message);
                    }
                } catch (e) {}
            }

            function post(type, reason) {
                sendMediaMessage({type:type, reason:reason || '', pageURL:location.href, documentID:playbackDocumentID});
            }

            function reportPictureInPictureState(event) {
                var video = event && event.target;
                var owner = playbackVideo || primaryVideo();
                if (!playbackConfirmed || !video || video !== owner || video.tagName !== 'VIDEO') return;
                var active = false;
                try {
                    active = document.pictureInPictureElement === video
                        || video.webkitPresentationMode === 'picture-in-picture'
                        || event.type === 'enterpictureinpicture';
                } catch (e) {
                    active = event.type === 'enterpictureinpicture';
                }
                sendMediaMessage({
                    type: 'picture_in_picture_state',
                    reason: active ? 'active' : 'inactive',
                    pageURL: location.href,
                    documentID: playbackDocumentID
                });
            }

            function isAdvertisingElement(element) {
                try {
                    return !!element.closest('[data-ad-slot], [data-ad], [id^="google_ads"], .adsbygoogle, .jw-flag-ads, .vjs-ad-playing, .vjs-ad-loading, .ima-ad-container, [class*="advertisement"], [id*="advertisement"]');
                } catch (e) { return true; }
            }

            function visibleArea(element) {
                try {
                    if (!element || element.isConnected === false || document.hidden || isAdvertisingElement(element)) return 0;
                    for (var node = element; node && node.nodeType === 1; node = node.parentElement) {
                        var style = window.getComputedStyle(node);
                        if (style.display === 'none' || (node === element && (style.visibility === 'hidden' || style.visibility === 'collapse'))
                            || Number(style.opacity) < 0.1) return 0;
                    }
                    var rect = element.getBoundingClientRect();
                    var width = Math.max(0, Math.min(rect.right, window.innerWidth) - Math.max(rect.left, 0));
                    var height = Math.max(0, Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0));
                    var area = width * height;
                    return width >= 120 && height >= 68 && area >= window.innerWidth * window.innerHeight * 0.20 ? area : 0;
                } catch (e) { return 0; }
            }

            function eligibleVideo(video) {
                return canOwnDocument && parentFrameEligible && videos().indexOf(video) !== -1
                    && !video.ended && visibleArea(video) > 0 && !isNuisanceURL(video.currentSrc || '');
            }

            function primaryVideo() {
                var candidates = videos().filter(eligibleVideo).sort(function(a,b) { return visibleArea(b) - visibleArea(a); });
                if (!candidates.length) return null;
                // Preserve the user's paused/buffering main player. Another
                // advancing video must not steal ownership from it.
                if (playbackVideo && candidates.indexOf(playbackVideo) !== -1) return playbackVideo;
                if (candidates.length > 1 && visibleArea(candidates[0]) < visibleArea(candidates[1]) * 1.5) return null;
                return candidates[0];
            }

            function releasePlaybackOwnership() {
                if (playbackConfirmed) post('playback_released');
                playbackConfirmed = false;
                playbackVideo = null;
                reportedTransportState = null;
                latestNativeCandidate = '';
                lastReportedNativeCandidate = '';
                lastProgressTime = 0;
            }

            function updateChildEligibility() {
                if (playbackSuspended || document.hidden) return;
                var frames = Array.prototype.slice.call(document.querySelectorAll('iframe'));
                childClaims.forEach(function(documents, frame) {
                    if (frames.indexOf(frame) === -1 || !parentFrameEligible || !visibleArea(frame) || isNuisanceURL(frame.src || '')) {
                        documents.forEach(function(id) { sendMediaMessage({type:'playback_released',documentID:id}); });
                        childClaims.delete(frame);
                    }
                });
                frames.forEach(function(frame) {
                    try {
                        frame.contentWindow.postMessage({type:'fotty_frame_eligibility', eligible:parentFrameEligible
                            && visibleArea(frame) > 0 && !isNuisanceURL(frame.src || '')}, '*');
                    } catch (e) {}
                });
            }

            function nativeCandidateURL(value) {
                if (!value || typeof value !== 'string') return '';
                try {
                    var absolute = new URL(value, location.href).href;
                    var normalized = absolute.toLowerCase();
                    if (!(normalized.startsWith('https://') || normalized.startsWith('http://'))) return '';
                    if (normalized.startsWith('blob:') || isNuisanceURL(normalized)) return '';
                    if (normalized.indexOf('.m3u8') === -1 && normalized.indexOf('.mp4') === -1) return '';
                    return absolute;
                } catch (e) {
                    return '';
                }
            }

            function reportNativeCandidateIfReady() {
                if (!playbackConfirmed || !latestNativeCandidate || latestNativeCandidate === lastReportedNativeCandidate) return;
                lastReportedNativeCandidate = latestNativeCandidate;
                try {
                    if (playbackVideo === primaryVideo()) {
                        sendMediaMessage({
                            type: 'native_candidate',
                            url: latestNativeCandidate,
                            pageURL: location.href,
                            documentID: playbackDocumentID,
                            userAgent: navigator.userAgent || ''
                        });
                    }
                } catch (e) {}
            }

            function rememberNativeCandidate(value) {
                var candidate = nativeCandidateURL(value);
                if (!candidate || !playbackConfirmed || playbackVideo !== primaryVideo()) return;
                latestNativeCandidate = candidate;
                reportNativeCandidateIfReady();
            }

            function inspectOwnedNativeSource(video) {
                if (!video || video !== playbackVideo || video !== primaryVideo()) return;
                // A resource request is not evidence of media ownership. Prefer
                // the active DOM source; MSE requires an explicitly bound player API.
                if (nativeCandidateURL(video.currentSrc)) {
                    rememberNativeCandidate(video.currentSrc);
                    return;
                }
                try {
                    var container = video.closest('.jwplayer');
                    var jw = container && container.id && window.jwplayer && window.jwplayer(container.id);
                    if (jw && typeof jw.getContainer === 'function' && jw.getContainer() === container
                        && container.contains(video) && typeof jw.getPlaylistItem === 'function') {
                        var item = jw.getPlaylistItem();
                        if (item) rememberNativeCandidate(item.file || (item.sources && item.sources[0] && item.sources[0].file));
                    }
                } catch (e) {}
                try {
                    var vjsContainer = video.closest('.video-js');
                    var player = vjsContainer && window.videojs && typeof window.videojs.getPlayer === 'function'
                        && window.videojs.getPlayer(vjsContainer.id);
                    if (player && typeof player.el === 'function' && player.el() === vjsContainer
                        && vjsContainer.contains(video) && typeof player.currentSource === 'function') {
                        rememberNativeCandidate(player.currentSource().src);
                    }
                } catch (e) {}
            }

            function videos() {
                try {
                    return Array.prototype.slice.call(document.querySelectorAll(
                        score808Site ? '#my-video video, video#my-video_html5_api' : 'video'
                    ));
                }
                catch (e) { return []; }
            }

            function focusScore808Player() {
                if (!score808Site || window !== window.top || !document.head || !document.getElementById('my-video')) return;
                var style = document.getElementById('fotty-score808-focus');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'fotty-score808-focus';
                    document.head.appendChild(style);
                }
                // Keep the publisher document, scripts, media, and player
                // controls intact. Only its article/site chrome leaves view.
                style.textContent = 'html,body{margin:0!important;padding:0!important;background:#000!important;overflow:hidden!important}'
                    + 'body *{visibility:hidden!important}'
                    + '#my-video,#my-video *{visibility:visible!important}'
                    + '#my-video{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:none!important;padding:0!important;margin:0!important;z-index:2147483000!important}'
                    + '#my-video video{object-fit:' + (fillVideo ? 'cover' : 'contain') + '!important}';
            }

            function applyContentModeToVideos() {
                var mode = fillVideo ? 'cover' : 'contain';
                try {
                    document.querySelectorAll('video').forEach(function(video) {
                        if (video.style && typeof video.style.setProperty === 'function') {
                            video.style.setProperty('object-fit', mode, 'important');
                        }
                    });
                } catch (e) {}
                focusScore808Player();
            }

            window.__fottySetContentMode = function(fill) {
                fillVideo = !!fill;
                applyContentModeToVideos();
                try {
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        if (frame.contentWindow) {
                            frame.contentWindow.postMessage(
                                { type: 'fotty_set_content_mode', fill: fillVideo },
                                '*'
                            );
                        }
                    });
                } catch (e) {}
            };

            function mediaElements() {
                try { return Array.prototype.slice.call(document.querySelectorAll('video, audio')); }
                catch (e) { return []; }
            }

            // Observation containment only. WebKit's public suspension API
            // owns transport and its prior-state restoration; calling pause()
            // here would destroy that playing-state snapshot.
            window.__fottySetNativeTransferSuspended = function(suspended, acknowledged) {
                nativeTransferSuspended = !!suspended;
                nativeTransferSuspensionAcknowledged = nativeTransferSuspended && acknowledged === true;
                if (!nativeTransferSuspended) {
                    lastProgressAt = Date.now();
                    if (playbackVideo) lastProgressTime = playbackVideo.currentTime;
                    stallNoticeSent = false;
                    failureReported = false;
                    reportedTransportState = null;
                }
                document.querySelectorAll('iframe').forEach(function(frame) {
                    if (frame.contentWindow) frame.contentWindow.postMessage({
                        type:'fotty_native_transfer_suspended', suspended:nativeTransferSuspended,
                        acknowledged:nativeTransferSuspensionAcknowledged, attemptID:playbackAttemptID
                    }, '*');
                });
            };

            window.__fottySetPlaybackSuspended = function(suspended) {
                playbackSuspended = !!suspended;
                if (!playbackSuspended) {
                    // Time intentionally spent in the background is not a stall.
                    lastProgressAt = Date.now();
                    if (playbackVideo) lastProgressTime = playbackVideo.currentTime;
                    stallNoticeSent = false;
                    failureReported = false;
                }
                var media = mediaElements();
                if (playbackSuspended) {
                    // WebKit may mark the document hidden before the app's
                    // suspension command arrives. Remember the confirmed owner,
                    // not a new visibility election during backgrounding.
                    if ([playbackVideo || primaryVideo()].filter(Boolean).some(function(item) { return !item.paused && !item.ended; })) {
                        resumeAfterSuspend = true;
                    }
                    media.forEach(function(item) {
                        try { item.pause(); } catch (e) {}
                    });
                    try {
                        var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                        var state = jw && typeof jw.getState === 'function' ? jw.getState() : null;
                        if (primaryVideo() && (state === 'playing' || state === 'buffering')) resumeAfterSuspend = true;
                        if (jw && typeof jw.pause === 'function') jw.pause(true);
                    } catch (e) {}
                } else if (resumeAfterSuspend) {
                    resumeAfterSuspend = false;
                    [primaryVideo()].filter(Boolean).forEach(function(item) {
                        try {
                            var promise = item.play && item.play();
                            if (promise && promise.catch) promise.catch(function() {});
                        } catch (e) {}
                    });
                    try {
                        var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                        if (jw && primaryVideo() && typeof jw.play === 'function') jw.play();
                    } catch (e) {}
                }
                try {
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        if (frame.contentWindow) {
                            frame.contentWindow.postMessage(
                                { type: 'fotty_set_suspended', suspended: playbackSuspended },
                                '*'
                            );
                        }
                    });
                } catch (e) {}
            };

            window.__fottySetPlaying = function(shouldPlay) {
                var playRequested = !!shouldPlay;
                playbackUserPaused = !playRequested;
                if (!playRequested) {
                    // Tapping the provider surface is how Fotty reveals its
                    // controls. That earlier touch is not permission for a
                    // provider script to undo the Pause command that follows.
                    // Only a new provider interaction after this command may
                    // be treated as the user's own Play request.
                    lastTrustedProviderInteractionAt = 0;
                }
                // A rejected play request must restore the truthful paused UI.
                function reportCommandResult() {
                    reportTransportState(playbackVideo, true);
                }
                (playRequested ? [primaryVideo()].filter(Boolean) : mediaElements()).forEach(function(item) {
                    try {
                        if (playRequested) {
                            var promise = item.play && item.play();
                            if (promise && promise.then) promise.then(reportCommandResult, reportCommandResult);
                        } else {
                            item.pause();
                        }
                    } catch (e) {}
                });
                try {
                    var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                    if (jw && primaryVideo()) {
                        if (playRequested && typeof jw.play === 'function') jw.play();
                        if (!playRequested && typeof jw.pause === 'function') jw.pause(true);
                    }
                } catch (e) {}
                try {
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        if (frame.contentWindow) {
                            frame.contentWindow.postMessage(
                                { type: 'fotty_set_playing', shouldPlay: playRequested },
                                '*'
                            );
                        }
                    });
                } catch (e) {}
                reportCommandResult();
            };

            function synchronizeMuteState() {
                if (providerControlsAudio) return;
                mediaElements().forEach(function(video) {
                    try {
                        video.muted = shouldMute;
                        video.defaultMuted = shouldMute;
                        video.volume = shouldMute ? 0 : 1;
                    } catch (e) {}
                });
                try {
                    var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                    if (jw && typeof jw.setMute === 'function') jw.setMute(shouldMute);
                    if (!shouldMute && jw && typeof jw.setVolume === 'function') jw.setVolume(100);
                } catch (e) {}
            }

            // Explicit Watch Two ownership transition; presentation, ordinary
            // provider taps and scroll updates never change the audio policy.
            window.__fottySetAudioOwnership = function(managed, muted) {
                if (typeof managed !== 'boolean' || typeof muted !== 'boolean') return;
                var wasManaged = !providerControlsAudio;
                shouldMute = muted;
                if (managed || wasManaged) {
                    providerControlsAudio = false;
                    synchronizeMuteState();
                }
                providerControlsAudio = !managed;
                document.querySelectorAll('iframe').forEach(function(frame) {
                    if (frame.contentWindow) frame.contentWindow.postMessage({ type:'fotty_audio_ownership', managed:managed, muted:muted }, '*');
                });
            };

            window.__fottySetMuted = function(muted) {
                if (providerControlsAudio) return;
                shouldMute = !!muted;
                synchronizeMuteState();
                try {
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        if (frame.contentWindow) {
                            frame.contentWindow.postMessage(
                                { type: 'fotty_set_muted', muted: shouldMute },
                                '*'
                            );
                        }
                    });
                } catch (e) {}
            };

            // A parent-script completion is not evidence that an opaque child
            // has muted. Only the actual decoded owner's readback may ACK.
            window.__fottyRevokeAudio = function(requestID, attemptID, ownerID, deadline) {
                if (typeof requestID !== 'string' || !requestID || requestID.length > 64
                    || attemptID !== playbackAttemptID || typeof ownerID !== 'string'
                    || !ownerID || ownerID.length > 160) return;
                if (typeof deadline !== 'number') deadline = Date.now() + 2000;
                if (!Number.isFinite(deadline) || deadline <= Date.now() || deadline > Date.now() + 2000) return;
                if (audioRevocationRequest && audioRevocationRequest.id === requestID
                    && audioRevocationRequest.owner === ownerID) return;
                audioRevocationRequest = {id:requestID, owner:ownerID, deadline:deadline, acknowledged:false};
                providerControlsAudio = false;
                shouldMute = true;
                synchronizeMuteState();
                try {
                    var media = mediaElements();
                    var owner = playbackVideo;
                    var verified = playbackConfirmed && playbackDocumentID === ownerID
                        && owner && owner === primaryVideo() && isDecoded(owner)
                        && media.indexOf(owner) !== -1 && media.every(function(item) {
                            return item.muted === true && item.defaultMuted === true && item.volume === 0;
                        });
                    if (verified && Date.now() <= deadline) {
                        audioRevocationRequest.acknowledged = true;
                        sendMediaMessage({type:'audio_revocation_ack', requestID:requestID,
                            attemptID:playbackAttemptID, documentID:playbackDocumentID});
                    }
                } catch (e) {}
                document.querySelectorAll('iframe').forEach(function(frame) {
                    try {
                        if (frame.contentWindow) frame.contentWindow.postMessage({type:'fotty_revoke_audio',
                            requestID:requestID, attemptID:attemptID, ownerID:ownerID, deadline:deadline}, '*');
                    } catch (e) {}
                });
            };

            window.addEventListener('message', function(event) {
                var data = event && event.data;
                if (!data) return;
                if (data.type === 'fotty_frame_eligibility' && window !== window.top && event.source === window.parent) {
                    if (playbackSuspended || document.hidden) return;
                    parentFrameEligible = canOwnDocument && data.eligible === true;
                    if (!parentFrameEligible) releasePlaybackOwnership();
                    updateChildEligibility();
                } else if (data.type === 'fotty_media_event') {
                    if (score808Site) return;
                    var frame = Array.prototype.find.call(document.querySelectorAll('iframe'), function(item) { return item.contentWindow === event.source; });
                    var message = data.message;
                    if (!frame || !message || typeof message.documentID !== 'string') return;
                    if (message.attemptID && message.attemptID !== playbackAttemptID) return;
                    var priorClaims = childClaims.get(frame);
                    if (message.type === 'audio_revocation_ack') {
                        var request = audioRevocationRequest;
                        if (!request || request.acknowledged || request.deadline < Date.now()
                            || message.requestID !== request.id || message.documentID !== request.owner
                            || message.attemptID !== playbackAttemptID
                            || !priorClaims || !priorClaims.has(message.documentID)) return;
                        request.acknowledged = true;
                        sendMediaMessage(message);
                        return;
                    }
                    if (message.type === 'playback_released') {
                        if (priorClaims && priorClaims.has(message.documentID)) {
                            priorClaims.delete(message.documentID);
                            sendMediaMessage(message);
                        }
                        return;
                    }
                    // Once a child document owns decoded playback, preserve its
                    // PiP lifecycle signal while the top page is becoming hidden.
                    // A visibility check here would lose the exact event that
                    // accompanies iOS moving the Fotty scene to the background.
                    if (message.type === 'picture_in_picture_state'
                        && priorClaims && priorClaims.has(message.documentID)) {
                        sendMediaMessage(message);
                        return;
                    }
                    if (!parentFrameEligible || !visibleArea(frame) || isNuisanceURL(frame.src || '')) return;
                    // A merely visible child may still be an ad or placeholder.
                    // Before decoded ownership, the top-level startup deadline
                    // remains authoritative; child error text cannot fail early.
                    if (message.type === 'stream_failed' && (!priorClaims || !priorClaims.has(message.documentID))) return;
                    if (message.type === 'playback_started') {
                        if (!priorClaims) { priorClaims = new Set(); childClaims.set(frame, priorClaims); }
                        priorClaims.add(message.documentID);
                    }
                    sendMediaMessage(message);
                } else if (event.source !== window.parent && event.source !== window) {
                    return;
                } else if (data.type === 'fotty_audio_ownership') {
                    window.__fottySetAudioOwnership(data.managed, data.muted);
                } else if (data.type === 'fotty_set_muted') {
                    window.__fottySetMuted(!!data.muted);
                } else if (data.type === 'fotty_revoke_audio') {
                    window.__fottyRevokeAudio(data.requestID, data.attemptID, data.ownerID, data.deadline);
                } else if (data.type === 'fotty_native_transfer_suspended') {
                    if (data.attemptID !== playbackAttemptID) return;
                    window.__fottySetNativeTransferSuspended(!!data.suspended, data.acknowledged === true);
                } else if (data.type === 'fotty_set_suspended') {
                    window.__fottySetPlaybackSuspended(!!data.suspended);
                } else if (data.type === 'fotty_set_playing') {
                    window.__fottySetPlaying(!!data.shouldPlay);
                } else if (data.type === 'fotty_set_content_mode') {
                    window.__fottySetContentMode(!!data.fill);
                }
            });

            var diagnosticStages = new Set();
            function reportMediaStage(video) {
                if (!video || !eligibleVideo(video) || video !== primaryVideo()) return;
                var stage = video.error ? 'media_failure' : (video.readyState >= 2 ? 'media_ready' : 'media_observed');
                if (diagnosticStages.has(stage)) return;
                diagnosticStages.add(stage);
                // Passive observations only, never a playback/recovery command.
                post('diagnostic_stage', stage);
            }
            function isDecoded(video) {
                return video && video.readyState >= 2 && video.videoWidth >= 160 && video.videoHeight >= 90;
            }

            function reportTransportState(video, force) {
                if (!playbackConfirmed || video !== playbackVideo || !video
                    || playbackSuspended || document.hidden || video.ended) return;
                if (nativeTransferSuspended && (nativeTransferSuspensionAcknowledged || !video.paused)) return;
                var state = video.paused ? 'paused' : 'playing';
                if (!force && reportedTransportState === state) return;
                reportedTransportState = state;
                // Time deliberately spent paused is not a playback stall.
                lastProgressAt = Date.now();
                lastProgressTime = video.currentTime;
                stallNoticeSent = false;
                failureReported = false;
                post('transport_state', state);
            }

            function inspectProgress(video) {
                if (playbackSuspended || nativeTransferSuspended || document.hidden) return;
                reportMediaStage(video);
                if (playbackUserPaused && video && !video.paused) {
                    // Some embeds restart their media immediately after a
                    // programmatic pause. Hold Fotty's explicit Pause unless a
                    // real touch inside the provider preceded this play event.
                    if (lastTrustedProviderInteractionAt > 0
                        && Date.now() - lastTrustedProviderInteractionAt <= 1500) {
                        playbackUserPaused = false;
                    } else {
                        try { video.pause(); } catch (e) {}
                        reportTransportState(video, true);
                        return;
                    }
                }
                if (playbackVideo && (!eligibleVideo(playbackVideo) || playbackVideo.isConnected === false)) releasePlaybackOwnership();
                if (video !== primaryVideo()) return;
                if (!isDecoded(video) || !Number.isFinite(video.currentTime) || video.isConnected === false) return;
                if (playbackVideo && video !== playbackVideo && playbackVideo.isConnected) return;
                if (playbackConfirmed && video !== playbackVideo) {
                    playbackVideo = video;
                    lastProgressTime = video.currentTime;
                } else if (video.currentTime < lastProgressTime - 0.1) {
                    lastProgressTime = video.currentTime;
                }
                // A replacement element or backward timeline discontinuity is
                // a new baseline, not recovery. Only subsequent forward progress
                // resets the watchdog, so a frozen replacement still times out.
                if (video.currentTime > lastProgressTime + 0.1) {
                    lastProgressTime = video.currentTime;
                    lastProgressAt = Date.now();
                    if (stallNoticeSent || failureReported) {
                        stallNoticeSent = false;
                        failureReported = false;
                        diagnosticStages.delete('buffering');
                        post('playback_recovered');
                    }
                    if (!playbackConfirmed && video.currentTime > 0.25 && !video.paused && !video.ended) {
                        playbackConfirmed = true;
                        playbackVideo = video;
                        lastOwnershipAnnouncement = Date.now();
                        post('playback_started');
                    }
                    inspectOwnedNativeSource(video);
                }
                reportTransportState(video, false);
            }

            function reportFailure(reason) {
                if (failureReported) return;
                failureReported = true;
                post('stream_failed', reason || 'Provider reported a playback error');
            }

            document.addEventListener('timeupdate', function(event) {
                inspectProgress(event.target);
            }, true);
            document.addEventListener('playing', function(event) {
                inspectProgress(event.target);
            }, true);
            document.addEventListener('pause', function(event) {
                reportTransportState(event.target, false);
            }, true);
            document.addEventListener('waiting', function(event) {
                if (playbackConfirmed && event.target === playbackVideo && !playbackSuspended
                    && !nativeTransferSuspended && !playbackUserPaused && !document.hidden && !diagnosticStages.has('buffering')) {
                    diagnosticStages.add('buffering');
                    post('diagnostic_stage', 'buffering');
                }
            }, true);
            document.addEventListener('enterpictureinpicture', reportPictureInPictureState, true);
            document.addEventListener('leavepictureinpicture', reportPictureInPictureState, true);
            document.addEventListener('webkitpresentationmodechanged', reportPictureInPictureState, true);
            document.addEventListener('pointerdown', function(event) {
                // Synthetic provider scripts cannot clear a user pause. A real
                // interaction may legitimately be the user pressing the
                // provider's own Play control.
                if (event && event.isTrusted !== false) {
                    lastTrustedProviderInteractionAt = Date.now();
                }
            }, true);
            document.addEventListener('error', function(event) {
                var video = event.target;
                if (video && video.tagName === 'VIDEO'
                    && video === primaryVideo()) {
                    reportMediaStage(video);
                    var detail = video.error ? ('Media error ' + video.error.code) : 'HTML5 video error';
                    reportFailure(detail);
                }
            }, true);

            // Playback controls can remain interactive, but provider popups and
            // known ad click-throughs must never escape the in-app player.
            document.addEventListener('click', function(event) {
                try {
                    var anchor = event.target && event.target.closest && event.target.closest('a');
                    if (!anchor) return;
                    var href = anchor.href || '';
                    if (isNuisanceURL(href)) {
                        event.preventDefault();
                        event.stopImmediatePropagation();
                    } else if (anchor.target === '_blank') {
                        // Block navigation, not the provider's JS play handler.
                        // WKUIDelegate and window.open still reject popups.
                        event.preventDefault();
                    }
                } catch (e) {}
            }, true);

            document.addEventListener('click', function() {
                post('surface_tapped');
            }, { capture: true, passive: true });

            removeNuisanceElements();
            applyContentModeToVideos();
            try {
                var nuisanceObserver = new MutationObserver(function() {
                    removeNuisanceElements();
                    applyContentModeToVideos();
                });
                nuisanceObserver.observe(document.documentElement, { childList: true, subtree: true });
            } catch (e) {}

            // Browser-parity first: let the provider initialize untouched. If it
            // has not started after 3.5 seconds, perform one restrained play kick.
            setTimeout(function() {
                if (playbackConfirmed || playbackSuspended || nativeTransferSuspended || playbackUserPaused
                    || document.hidden || !parentFrameEligible) return;
                var allVideos = [primaryVideo()].filter(Boolean);
                var alreadyPlaying = allVideos.some(function(video) {
                    return isDecoded(video) && !video.paused && !video.ended && video.currentTime > 0.1;
                });
                if (alreadyPlaying) {
                    allVideos.forEach(inspectProgress);
                    return;
                }

                try {
                    var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                    if (jw) {
                        var state = typeof jw.getState === 'function' ? jw.getState() : null;
                        if (!providerControlsAudio && typeof jw.setMute === 'function') jw.setMute(shouldMute);
                        if (state !== 'playing' && state !== 'buffering' && typeof jw.play === 'function') jw.play();
                    }
                } catch (e) {}

                allVideos.forEach(function(video) {
                    try {
                        video.playsInline = true;
                        if (!providerControlsAudio) video.muted = shouldMute;
                        video.setAttribute('playsinline', '');
                        video.setAttribute('webkit-playsinline', '');
                        var promise = video.play && video.play();
                        if (promise && promise.catch) promise.catch(function() {});
                    } catch (e) {}
                });

                if (allVideos.length === 0) {
                    var selectors = ['.jw-icon-playback', '.vjs-big-play-button', '[aria-label="Play"]', 'button[title="Play"]', '[data-player-play]'];
                    for (var index = 0; index < selectors.length; index++) {
                        var control = document.querySelector(selectors[index]);
                        if (control && typeof control.click === 'function') {
                            try { control.click(); } catch (e) {}
                            break;
                        }
                    }
                }
            }, 3500);

            try {
                var errorObserver = new MutationObserver(function() {
                    if (playbackSuspended || document.hidden || !parentFrameEligible) return;
                    var selected = primaryVideo();
                    if (selected) {
                        var container = selected.closest('.jwplayer, .video-js');
                        var element = container && container.querySelector('.jw-error-msg, .jw-error, .jw-media-error, .vjs-error-display');
                        if (element && !isAdvertisingElement(element) && element.textContent && element.textContent.trim()) {
                            var style = window.getComputedStyle(element), rect = element.getBoundingClientRect();
                            if (style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) !== 0
                                && rect.width > 0 && rect.height > 0) reportFailure(element.textContent.trim());
                        }
                    }
                    // Once a main player is known, page-wide prose/ad errors
                    // cannot contradict its actual decoded media state.
                    if (playbackConfirmed || selected) return;
                    var bodyText = document.body && document.body.innerText
                        ? document.body.innerText.toLowerCase()
                        : '';
                    if (bodyText.indexOf('embedding disabled') !== -1
                        || bodyText.indexOf('channel is unavailable') !== -1
                        || bodyText.indexOf('stream is unavailable') !== -1) {
                        reportFailure('Provider reports this broadcast is unavailable');
                    }
                });
                errorObserver.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
            } catch (e) {}

            setInterval(function() {
                if (nativeTransferSuspended) return;
                focusScore808Player();
                updateChildEligibility();
                if (playbackSuspended) {
                    mediaElements().forEach(function(media) {
                        try { media.pause(); } catch (e) {}
                    });
                    return;
                }
                if (document.hidden) return;
                if (playbackUserPaused) {
                    mediaElements().forEach(function(media) {
                        if (!media.paused) {
                            try { media.pause(); } catch (e) {}
                        }
                    });
                    return;
                }
                synchronizeMuteState();
                if (playbackVideo && !eligibleVideo(playbackVideo)) releasePlaybackOwnership();
                videos().forEach(inspectProgress);
                // Re-announce only an advancing owner. This lets a replacement
                // iframe acquire ownership after its removed predecessor releases.
                if (playbackConfirmed && Date.now() - lastProgressAt < 2000
                    && Date.now() - lastOwnershipAnnouncement >= 2000) {
                    lastOwnershipAnnouncement = Date.now();
                    post('playback_started');
                }
                inspectOwnedNativeSource(playbackVideo);
            }, 500);

            setTimeout(function() {
                // Child frames report their own decoded playback. Only the main
                // frame owns the overall startup deadline, avoiding blank/ad
                // iframe watchdogs racing the real player.
                if (window === window.top && !playbackConfirmed) {
                    reportFailure('Startup timeout: no decoded video within \(Int(LivePlaybackPolicy.webStartupFailureSeconds)) seconds');
                }
            }, \(Int(LivePlaybackPolicy.webStartupFailureSeconds * 1_000)));

            setInterval(function() {
                if (!playbackConfirmed || playbackSuspended || nativeTransferSuspended || document.hidden) return;
                var expectsProgress = playbackVideo && !playbackVideo.paused && !playbackVideo.ended;
                var stalledFor = Date.now() - lastProgressAt;
                if (expectsProgress && stalledFor > 10000 && !stallNoticeSent) {
                    stallNoticeSent = true;
                    post('playback_buffering');
                }
                if (expectsProgress && stalledFor > \(Int(LivePlaybackPolicy.webStallFailureSeconds * 1_000))) {
                    reportFailure('Playback stalled: decoded playhead stopped advancing');
                }
            }, 1000);
        })();
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var loadedEmbedURL: URL?
        var loadedAttemptID: UUID?
        var lastReferer = ""
        var lastMuted = false
        var lastSuspended = false
        var lastFillMode = false
        var providerControlsAudio = false
        var lastPlaybackCommandID: UUID?
        var lastPlaybackCommandShouldPlay: Bool?
        var loadStartedAt = Date()
        var hasReportedFailure = false
        var hasReportedPlayback = false
        var playbackDocumentID: String?
        var isAcceptingMessages = false
        var pendingFailureTask: DispatchWorkItem?
        var startupFailureTask: DispatchWorkItem?
        var audioConfigurationTask: Task<Void, Never>?
        var activeNavigation: WKNavigation?
        var committedDocumentURL: URL?
        private var loadingGeneration = UUID()
        private var audioConfigurationID = UUID()
        private let configureAudioSession: @MainActor () async -> MediaAudioSessionPreparation
        private let timing: FottyAsyncTiming
        private var isTransportPaused = false
        private var failedDocumentReason: String?
        private var admittedNavigationGeneration: UUID?
        private let retiredNavigations = NSHashTable<WKNavigation>.weakObjects()
        private var hasCommittedSelectedLoad = false
        private struct WebAudioRevocationRequest {
            let id: UUID
            let loadingGeneration: UUID
            let attemptID: UUID
            let documentID: String
            let webViewID: ObjectIdentifier
            let deadline: TimeInterval
        }
        private struct DesiredWebAudioRevocation {
            let id: UUID
            let loadingGeneration: UUID
            let attemptID: UUID
            let webViewID: ObjectIdentifier
            let deadline: TimeInterval
        }
        private var desiredWebAudioRevocation: DesiredWebAudioRevocation?
        private var observedWebAudioRevocationID: UUID?
        private var lastWebAudioRevocationID: UUID?
        private var webAudioRevocationRequest: WebAudioRevocationRequest?
        @MainActor private final class NativeTransferSuspensionLease {
            let id: UUID
            let generation: UUID
            let loadingGeneration: UUID
            let attemptID: UUID
            let documentID: String
            weak var webView: WKWebView?
            let originalUserInteractionEnabled: Bool
            var inputShieldRestored = false
            var suspensionAcknowledged = false
            var authorizationRevoked = false

            init(id: UUID, generation: UUID, loadingGeneration: UUID, attemptID: UUID,
                 documentID: String, webView: WKWebView) {
                self.id = id; self.generation = generation; self.loadingGeneration = loadingGeneration
                self.attemptID = attemptID; self.documentID = documentID; self.webView = webView
                originalUserInteractionEnabled = webView.isUserInteractionEnabled
            }
        }
        private var nativeTransferGeneration = UUID()
        private var desiredNativeTransferSuspensionID: UUID?
        private var nativeTransferSuspensionLease: NativeTransferSuspensionLease?
        private var nativeTransferSuspensionOperationInFlight = false
        var onSurfaceTapped: (() -> Void)?
        var onDiagnosticStage: ((FottyPlaybackStage, Int?) -> Void)?
        var onAudioPreparationMeasured: ((Int, MediaAudioSessionPreparation) -> Void)?
        private var reportedDiagnosticStages = Set<FottyPlaybackStage>()
        var onTransportStateChanged: ((WebPlaybackTransportState) -> Void)?
        var onPlaybackStarted: ((Int) -> Void)?
        var onPlaybackStalled: ((String) -> Void)?
        var onPlaybackRecovered: (() -> Void)?
        var onPictureInPictureActiveChanged: ((Bool) -> Void)?
        var onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)?
        var onPlaybackRetired: (() -> Void)?
        var onNativeTransferSuspensionChanged: (UUID, Bool) -> Void
        var onWebAudioRevocationAcknowledged: (UUID) -> Void
        var lastNativeCandidateURL: URL?
        var isPictureInPictureActive = false

        init(
            onSurfaceTapped: (() -> Void)? = nil,
            onDiagnosticStage: ((FottyPlaybackStage, Int?) -> Void)? = nil,
            onAudioPreparationMeasured: ((Int, MediaAudioSessionPreparation) -> Void)? = nil,
            onTransportStateChanged: ((WebPlaybackTransportState) -> Void)? = nil,
            onPlaybackStarted: ((Int) -> Void)? = nil,
            onPlaybackStalled: ((String) -> Void)? = nil,
            onPlaybackRecovered: (() -> Void)? = nil,
            onPictureInPictureActiveChanged: ((Bool) -> Void)? = nil,
            onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)? = nil,
            onPlaybackRetired: (() -> Void)? = nil,
            onNativeTransferSuspensionChanged: @escaping (UUID, Bool) -> Void = { _, _ in },
            onWebAudioRevocationAcknowledged: @escaping (UUID) -> Void = { _ in },
            configureAudioSession: @escaping @MainActor () async -> MediaAudioSessionPreparation = {
                await MediaAudioSession.configureForPlayback()
            },
            timing: FottyAsyncTiming? = nil
        ) {
            self.onSurfaceTapped = onSurfaceTapped
            self.onDiagnosticStage = onDiagnosticStage
            self.onAudioPreparationMeasured = onAudioPreparationMeasured
            self.onTransportStateChanged = onTransportStateChanged
            self.onPlaybackStarted = onPlaybackStarted
            self.onPlaybackStalled = onPlaybackStalled
            self.onPlaybackRecovered = onPlaybackRecovered
            self.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
            self.onNativeCandidateDiscovered = onNativeCandidateDiscovered
            self.onPlaybackRetired = onPlaybackRetired
            self.onNativeTransferSuspensionChanged = onNativeTransferSuspensionChanged
            self.onWebAudioRevocationAcknowledged = onWebAudioRevocationAcknowledged
            self.configureAudioSession = configureAudioSession
            self.timing = timing ?? .live
        }

        func beginLoading(url: URL, referer: String, attemptID: UUID) {
            invalidateLoading()
            loadedEmbedURL = url
            loadedAttemptID = attemptID
            lastReferer = referer
            loadStartedAt = Date()
            reportedDiagnosticStages.removeAll()
            hasReportedFailure = false
            hasReportedPlayback = false
            playbackDocumentID = nil
            lastNativeCandidateURL = nil
            failedDocumentReason = nil
            isTransportPaused = false
            lastPlaybackCommandShouldPlay = nil
            armStartupDeadline()
        }

        func invalidateLoading() {
            audioConfigurationTask?.cancel()
            audioConfigurationTask = nil
            audioConfigurationID = UUID()
            loadingGeneration = UUID()
            webAudioRevocationRequest = nil
            desiredWebAudioRevocation = nil
            lastWebAudioRevocationID = nil
            invalidateNativeTransferSuspension()
            isAcceptingMessages = false
            if let activeNavigation { retiredNavigations.add(activeNavigation) }
            activeNavigation = nil
            committedDocumentURL = nil
            admittedNavigationGeneration = nil
            hasCommittedSelectedLoad = false
            pendingFailureTask?.cancel()
            pendingFailureTask = nil
            startupFailureTask?.cancel()
            startupFailureTask = nil
        }

        func requestWebAudioRevocation(_ id: UUID?) {
            if observedWebAudioRevocationID == id {
                reconcileWebAudioRevocation()
                return
            }
            observedWebAudioRevocationID = id
            desiredWebAudioRevocation = nil
            lastWebAudioRevocationID = nil
            webAudioRevocationRequest = nil
            guard let id, let webView, let attempt = loadedAttemptID, !providerControlsAudio else { return }
            desiredWebAudioRevocation = DesiredWebAudioRevocation(id: id,
                loadingGeneration: loadingGeneration, attemptID: attempt,
                webViewID: ObjectIdentifier(webView), deadline: timing.monotonicNow() + 2)
            reconcileWebAudioRevocation()
        }

        private func reconcileWebAudioRevocation() {
            guard let desired = desiredWebAudioRevocation, lastWebAudioRevocationID != desired.id,
                  let webView, loadedAttemptID == desired.attemptID,
                  loadingGeneration == desired.loadingGeneration,
                  ObjectIdentifier(webView) == desired.webViewID,
                  timing.monotonicNow() <= desired.deadline,
                  let document = playbackDocumentID, hasReportedPlayback,
                  isAcceptingMessages, isCurrentDocument, !providerControlsAudio,
                  let data = try? JSONEncoder().encode([desired.id.uuidString, desired.attemptID.uuidString, document]),
                  let arguments = String(data: data, encoding: .utf8) else { return }
            lastWebAudioRevocationID = desired.id
            webAudioRevocationRequest = WebAudioRevocationRequest(id: desired.id,
                loadingGeneration: desired.loadingGeneration, attemptID: desired.attemptID, documentID: document,
                webViewID: desired.webViewID, deadline: desired.deadline)
            // Completion here would only acknowledge main-frame execution, not
            // the decoded child. The bridge receipt below is authoritative.
            webView.evaluateJavaScript("window.__fottyRevokeAudio && window.__fottyRevokeAudio.apply(null, \(arguments));")
        }

        private func acknowledgeWebAudioRevocation(_ body: [String: Any]) {
            guard let request = webAudioRevocationRequest, let webView,
                  request.id == lastWebAudioRevocationID,
                  request.id == desiredWebAudioRevocation?.id,
                  body["requestID"] as? String == request.id.uuidString,
                  body["attemptID"] as? String == request.attemptID.uuidString,
                  body["documentID"] as? String == request.documentID,
                  loadedAttemptID == request.attemptID, playbackDocumentID == request.documentID,
                  loadingGeneration == request.loadingGeneration,
                  ObjectIdentifier(webView) == request.webViewID,
                  timing.monotonicNow() <= request.deadline, hasReportedPlayback,
                  isAcceptingMessages, isCurrentDocument, !providerControlsAudio else { return }
            webAudioRevocationRequest = nil
            onWebAudioRevocationAcknowledged(request.id)
        }

        /// One owned true/false pair. WKWebView counts suspension requests, so
        /// rerenders and replacement IDs must not issue overlapping setters.
        func requestNativeTransferSuspension(_ id: UUID?) {
            desiredNativeTransferSuspensionID = id
            if let lease = nativeTransferSuspensionLease, id != lease.id {
                revokeNativeTransferAuthorization(lease)
            }
            reconcileNativeTransferSuspension()
        }

        private func revokeNativeTransferAuthorization(_ lease: NativeTransferSuspensionLease) {
            guard !lease.authorizationRevoked else { return }
            lease.authorizationRevoked = true
            // A release ACK cannot be used for revocation: a document can be
            // replaced while the native decoder is already preparing to adopt.
            onNativeTransferSuspensionChanged(lease.id, false)
        }

        private func restoreNativeTransferInputShield(_ lease: NativeTransferSuspensionLease) {
            guard !lease.inputShieldRestored else { return }
            lease.inputShieldRestored = true
            // Do not enable an originally disabled view or undo a subsequent
            // external enable. Only release the false value this lease imposed.
            if lease.originalUserInteractionEnabled, let webView = lease.webView,
               !webView.isUserInteractionEnabled { webView.isUserInteractionEnabled = true }
        }

        private func isCurrentNativeTransferLease(_ lease: NativeTransferSuspensionLease) -> Bool {
            nativeTransferGeneration == lease.generation && loadingGeneration == lease.loadingGeneration
                && loadedAttemptID == lease.attemptID && playbackDocumentID == lease.documentID
                && webView === lease.webView && lease.webView != nil && hasReportedPlayback
                && isAcceptingMessages && isCurrentDocument
        }

        private func invalidateNativeTransferSuspension() {
            nativeTransferGeneration = UUID()
            desiredNativeTransferSuspensionID = nil
            if let lease = nativeTransferSuspensionLease {
                revokeNativeTransferAuthorization(lease)
                restoreNativeTransferInputShield(lease)
            }
            // An uncancellable acquire still needs its matching release. Its
            // stale ACK may balance the platform but cannot authorize playback.
            reconcileNativeTransferSuspension()
        }

        private func reconcileNativeTransferSuspension() {
            guard !nativeTransferSuspensionOperationInFlight else { return }
            if let lease = nativeTransferSuspensionLease {
                guard desiredNativeTransferSuspensionID != lease.id || !isCurrentNativeTransferLease(lease)
                        || lease.authorizationRevoked || isTransportPaused || lastSuspended else { return }
                revokeNativeTransferAuthorization(lease)
                releaseNativeTransferSuspension(lease)
                return
            }
            guard let id = desiredNativeTransferSuspensionID, let webView,
                  let attempt = loadedAttemptID, let document = playbackDocumentID,
                  hasReportedPlayback, isAcceptingMessages, isCurrentDocument,
                  !lastSuspended, !isTransportPaused else { return }
            let lease = NativeTransferSuspensionLease(id: id, generation: nativeTransferGeneration,
                loadingGeneration: loadingGeneration, attemptID: attempt, documentID: document, webView: webView)
            nativeTransferSuspensionLease = lease
            nativeTransferSuspensionOperationInFlight = true
            if lease.originalUserInteractionEnabled { webView.isUserInteractionEnabled = false }
            pendingFailureTask?.cancel(); pendingFailureTask = nil
            startupFailureTask?.cancel(); startupFailureTask = nil
            setNativeTransferMonitorSuspended(true, in: webView)
            webView.setAllMediaPlaybackSuspended(true) { [weak self, weak lease] in
                guard let self, let lease, self.nativeTransferSuspensionLease === lease else { return }
                self.nativeTransferSuspensionOperationInFlight = false
                lease.suspensionAcknowledged = true
                if let webView = lease.webView {
                    self.setNativeTransferMonitorSuspended(true, acknowledged: true, in: webView)
                }
                if self.desiredNativeTransferSuspensionID == lease.id,
                   !lease.authorizationRevoked, self.isCurrentNativeTransferLease(lease),
                   !self.isTransportPaused, !self.lastSuspended {
                    self.onNativeTransferSuspensionChanged(lease.id, true)
                }
                self.reconcileNativeTransferSuspension()
            }
        }

        private func releaseNativeTransferSuspension(_ lease: NativeTransferSuspensionLease) {
            guard let webView = lease.webView else {
                nativeTransferSuspensionLease = nil
                reconcileNativeTransferSuspension()
                return
            }
            nativeTransferSuspensionOperationInFlight = true
            let release: @MainActor @Sendable () -> Void = { [weak self, weak lease, weak webView] in
                guard let self, let lease, let webView,
                      self.nativeTransferSuspensionLease === lease else { return }
                webView.setAllMediaPlaybackSuspended(false) { [weak self, weak lease, weak webView] in
                    guard let self, let lease, let webView,
                          self.nativeTransferSuspensionLease === lease else { return }
                    self.nativeTransferSuspensionOperationInFlight = false
                    self.nativeTransferSuspensionLease = nil
                    self.restoreNativeTransferInputShield(lease)
                    self.setNativeTransferMonitorSuspended(false, in: webView)
                    self.reconcileNativeTransferSuspension()
                }
            }
            // Public interruption release restores the platform's prior state.
            // Preserve an explicit Pause received while interrupted before
            // releasing that state; this is never an unconditional Play.
            if isCurrentNativeTransferLease(lease),
               lastPlaybackCommandShouldPlay == false || isTransportPaused || lastSuspended {
                webView.pauseAllMediaPlayback(completionHandler: release)
            } else { release() }
        }

        private func setNativeTransferMonitorSuspended(_ suspended: Bool, acknowledged: Bool = false,
                                                       in webView: WKWebView) {
            webView.evaluateJavaScript("window.__fottySetNativeTransferSuspended && window.__fottySetNativeTransferSuspended(\(suspended ? "true" : "false"), \(acknowledged ? "true" : "false"));")
        }

        func loadAfterAudioConfiguration(_ request: URLRequest, in webView: WKWebView) {
            audioConfigurationTask?.cancel()
            audioConfigurationID = UUID()
            let configurationID = audioConfigurationID
            let generation = loadingGeneration
            let attempt = loadedAttemptID
            // beginLoading owns the old deadline; audio preparation is not
            // provider startup time, so arm again only when navigation begins.
            startupFailureTask?.cancel()
            startupFailureTask = nil
            audioConfigurationTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, !Task.isCancelled,
                      self.webView === webView, self.audioConfigurationID == configurationID else { return }
                defer {
                    if self.audioConfigurationID == configurationID { self.audioConfigurationTask = nil }
                }
                let preparationStartedAt = self.timing.monotonicNow()
                let prepared = await self.configureAudioSession()
                guard !Task.isCancelled,
                      self.webView === webView, self.loadingGeneration == generation,
                      self.audioConfigurationID == configurationID,
                      self.loadedAttemptID == attempt, let url = self.loadedEmbedURL else { return }
                if let milliseconds = FottyPlaybackIntervals.elapsedMilliseconds(
                    from: preparationStartedAt, to: self.timing.monotonicNow()) {
                    self.onAudioPreparationMeasured?(milliseconds, prepared)
                }
                guard prepared.mayContinue else { return }
                // Commands can arrive while the document is still blank. Seed
                // the new document from current intent, not pre-await flags.
                LiveWebEmbedPlayerView.configurePlaybackMonitor(
                    in: webView.configuration.userContentController, url: url,
                    isMuted: self.lastMuted, providerControlsAudio: self.providerControlsAudio,
                    isSuspended: self.lastSuspended, isFillMode: self.lastFillMode,
                    attemptID: attempt, isUserPaused: self.isTransportPaused
                )
                self.loadStartedAt = Date()
                self.audioConfigurationTask = nil
                self.activeNavigation = webView.load(request)
                self.armStartupDeadline()
            }
        }

        private func armStartupDeadline() {
            startupFailureTask?.cancel()
            startupFailureTask = nil
            guard audioConfigurationTask == nil, loadedAttemptID != nil, !lastSuspended, !isTransportPaused,
                  !hasReportedPlayback, !hasReportedFailure else { return }
            let expectedGeneration = loadingGeneration
            let expectedAttempt = loadedAttemptID
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.loadingGeneration == expectedGeneration,
                      self.loadedAttemptID == expectedAttempt,
                      !self.lastSuspended, !self.isTransportPaused,
                      !self.hasReportedPlayback, !self.hasReportedFailure else { return }
                self.startupFailureTask = nil
                self.reportFailure(LivePlaybackPolicy.deferredStartupFailureReason("Web document did not start"))
            }
            startupFailureTask = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + LivePlaybackPolicy.webStartupFailureSeconds,
                execute: work
            )
        }

        func playbackSuspensionChanged(_ suspended: Bool) {
            lastSuspended = suspended
            if suspended {
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                startupFailureTask?.cancel()
                startupFailureTask = nil
                hasReportedFailure = false
            } else if let reason = failedDocumentReason {
                resumeFailedDocument(reason)
            } else if !hasReportedPlayback {
                // Background time is not a startup failure. Allow a fresh
                // bounded foreground opportunity without replacing the source.
                loadStartedAt = Date()
                armStartupDeadline()
            }
        }

        func playbackCommandWillApply(_ command: WebPlaybackCommand) {
            lastPlaybackCommandShouldPlay = command.shouldPlay
            isTransportPaused = !command.shouldPlay
            if isTransportPaused {
                requestNativeTransferSuspension(nil)
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                startupFailureTask?.cancel()
                startupFailureTask = nil
                hasReportedFailure = false
            } else if let reason = failedDocumentReason {
                resumeFailedDocument(reason)
            } else if !hasReportedPlayback {
                loadStartedAt = Date()
                armStartupDeadline()
            }
        }

        func reportDiagnosticStage(_ stage: FottyPlaybackStage, errorCode: Int? = nil) {
            if stage == .documentLoaded,
               !reportedDiagnosticStages.isDisjoint(with: [.mediaObserved, .mediaReady, .decoded]) { return }
            guard loadedAttemptID != nil, reportedDiagnosticStages.insert(stage).inserted else { return }
            onDiagnosticStage?(stage, errorCode)
        }

        private func reportDocumentFailure(_ reason: String) {
            failedDocumentReason = reason
            guard !lastSuspended, !isTransportPaused else { return }
            var body: [String: Any] = ["type": "stream_failed", "reason": reason]
            if let loadedAttemptID { body["attemptID"] = loadedAttemptID.uuidString }
            if let playbackDocumentID { body["documentID"] = playbackDocumentID }
            handlePlaybackMessage(body)
        }

        private func resumeFailedDocument(_ reason: String) {
            let expectedGeneration = loadingGeneration
            let expectedAttempt = loadedAttemptID
            // UIView updates must not synchronously publish SwiftUI playback
            // state. Recheck intent and ownership after leaving that update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadingGeneration == expectedGeneration,
                      self.loadedAttemptID == expectedAttempt,
                      self.failedDocumentReason == reason,
                      !self.lastSuspended, !self.isTransportPaused else { return }
                self.reportDocumentFailure(reason)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "fottyPlayerBridge",
                  message.frameInfo.isMainFrame,
                  isAcceptingMessages,
                  isCurrentDocument,
                  Self.sameDocumentURL(message.frameInfo.request.url, committedDocumentURL),
                  let body = message.body as? [String: Any] else { return }
            handlePlaybackMessage(body)
        }

        func handlePlaybackMessage(_ body: [String: Any]) {
            if let loadedAttemptID {
                guard body["attemptID"] as? String == loadedAttemptID.uuidString else { return }
            }
            guard let type = body["type"] as? String else { return }
            // Child/ad frames have independent monitors. After decoding starts,
            // only the owning document may fail, recover, or hand off that stream.
            if hasReportedPlayback,
                ["diagnostic_stage", "transport_state", "stream_failed", "playback_recovered", "native_candidate", "playback_released", "picture_in_picture_state", "audio_revocation_ack"].contains(type) {
                guard let documentID = body["documentID"] as? String,
                      documentID == playbackDocumentID else { return }
            }

            // Before the WK acquire ACK, a queued provider Pause could be a
            // genuine user action. Conservatively cancel and forward it; even
            // an expected platform Pause is safer than overriding that intent.
            let ownsNativeTransferInterruption = nativeTransferSuspensionLease.map(isCurrentNativeTransferLease) == true
            let acquiringPause = ownsNativeTransferInterruption && type == "transport_state"
                && body["reason"] as? String == "paused"
                && nativeTransferSuspensionLease?.suspensionAcknowledged == false
            if acquiringPause { requestNativeTransferSuspension(nil) }
            // Once acknowledged, provider input stays shielded until release.
            // This contains only the exact owned interruption, never ordinary
            // unknown pauses or a new decoded recovery claim.
            if ownsNativeTransferInterruption, !acquiringPause,
               type == "transport_state" || type == "playback_recovered"
                    || (type == "diagnostic_stage" && body["reason"] as? String == "buffering") { return }

            switch type {
            case "audio_revocation_ack":
                acknowledgeWebAudioRevocation(body)
            case "diagnostic_stage":
                guard !lastSuspended, !isTransportPaused,
                      let raw = body["reason"] as? String,
                      let stage = FottyPlaybackStage(rawValue: raw),
                      [.mediaObserved, .mediaReady, .mediaFailure, .buffering].contains(stage) else { return }
                if hasReportedPlayback, ![.mediaFailure, .buffering].contains(stage) { return }
                reportDiagnosticStage(stage)
            case "surface_tapped":
                onSurfaceTapped?()
            case "playback_started":
                guard !hasReportedPlayback, let documentID = body["documentID"] as? String,
                      !documentID.isEmpty else { return }
                hasReportedPlayback = true
                reportDiagnosticStage(.decoded)
                playbackDocumentID = documentID
                reconcileWebAudioRevocation()
                reconcileNativeTransferSuspension()
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                startupFailureTask?.cancel()
                startupFailureTask = nil
                failedDocumentReason = nil
                let latency = max(0, Int(Date().timeIntervalSince(loadStartedAt) * 1_000))
                // Keep start and subsequent transport events in WebKit order.
                onPlaybackStarted?(latency)
            case "playback_released":
                guard hasReportedPlayback else { return }
                webAudioRevocationRequest = nil
                desiredWebAudioRevocation = nil
                invalidateNativeTransferSuspension()
                if isPictureInPictureActive {
                    isPictureInPictureActive = false
                    onPictureInPictureActiveChanged?(false)
                }
                hasReportedPlayback = false
                playbackDocumentID = nil
                lastNativeCandidateURL = nil
                hasReportedFailure = false
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                loadStartedAt = Date()
                armStartupDeadline()
                // A removed/hidden/preroll document must not retain ownership.
                // Give its replacement a bounded startup opportunity, not an
                // immediate failover and not an indefinitely silent wait.
                handlePlaybackMessage([
                    "type": "stream_failed",
                    "reason": "Replacement player has not resumed decoded playback",
                    "attemptID": loadedAttemptID?.uuidString ?? ""
                ])
            case "transport_state":
                guard hasReportedPlayback,
                      !lastSuspended,
                      let documentID = body["documentID"] as? String,
                      documentID == playbackDocumentID,
                      let rawState = body["reason"] as? String,
                      let state = WebPlaybackTransportState(rawValue: rawState) else { return }
                if state == .paused {
                    isTransportPaused = true
                    pendingFailureTask?.cancel()
                    pendingFailureTask = nil
                    hasReportedFailure = false
                } else {
                    isTransportPaused = false
                }
                onTransportStateChanged?(state)
            case "stream_failed":
                guard !hasReportedFailure else { return }
                let reason = body["reason"] as? String ?? "Unknown provider error"
                if hasReportedPlayback,
                   reason.localizedCaseInsensitiveContains("startup timeout") {
                    return
                }
                let isExplicitProviderRejection = LivePlaybackPolicy
                    .isExplicitProviderRejection(reason)
                if !hasReportedPlayback, !isExplicitProviderRejection {
                    // Nested frames often contain short-lived ad players. Keep
                    // their first error as useful context, but give the actual
                    // provider player the full startup window to decode.
                    let remaining = max(
                        0,
                        LivePlaybackPolicy.webStartupFailureSeconds
                            - Date().timeIntervalSince(loadStartedAt)
                    )
                    if remaining > 0.1 {
                        pendingFailureTask?.cancel()
                        let expectedURL = loadedEmbedURL
                        let expectedAttemptID = loadedAttemptID
                        let expectedGeneration = loadingGeneration
                        let work = DispatchWorkItem { [weak self] in
                            guard let self,
                                  self.loadingGeneration == expectedGeneration,
                                  self.loadedEmbedURL == expectedURL,
                                  self.loadedAttemptID == expectedAttemptID,
                                  !self.lastSuspended,
                                  !self.isTransportPaused,
                                  !self.hasReportedPlayback,
                                  !self.hasReportedFailure else { return }
                            self.reportFailure(
                                LivePlaybackPolicy.deferredStartupFailureReason(reason)
                            )
                        }
                        pendingFailureTask = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
                        return
                    }
                }
                if hasReportedPlayback {
                    pendingFailureTask?.cancel()
                    let expectedURL = loadedEmbedURL
                    let expectedAttemptID = loadedAttemptID
                    let expectedGeneration = loadingGeneration
                    let work = DispatchWorkItem { [weak self] in
                        guard let self,
                              self.loadingGeneration == expectedGeneration,
                              self.loadedEmbedURL == expectedURL,
                              self.loadedAttemptID == expectedAttemptID,
                              !self.lastSuspended,
                              !self.isTransportPaused,
                              !self.hasReportedFailure else { return }
                        self.reportFailure(reason)
                    }
                    pendingFailureTask = work
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + LivePlaybackPolicy.webRecoveryGraceSeconds,
                        execute: work
                    )
                    return
                }
                reportFailure(reason)
            case "playback_recovered":
                guard hasReportedPlayback else { return }
                reportedDiagnosticStages.remove(.buffering)
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                hasReportedFailure = false
                failedDocumentReason = nil
                onPlaybackRecovered?()
            case "picture_in_picture_state":
                guard hasReportedPlayback,
                      let rawState = body["reason"] as? String,
                      ["active", "inactive"].contains(rawState) else { return }
                let active = rawState == "active"
                guard active != isPictureInPictureActive else { return }
                isPictureInPictureActive = active
                onPictureInPictureActiveChanged?(active)
            case "native_candidate":
                guard hasReportedPlayback,
                      let rawURL = body["url"] as? String,
                      let url = URL(string: rawURL),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url != lastNativeCandidateURL else { return }
                lastNativeCandidateURL = url
                let pageURL = (body["pageURL"] as? String).flatMap(URL.init(string:))
                let referer = pageURL?.absoluteString ?? lastReferer
                let userAgent = body["userAgent"] as? String
                let expectedAttemptID = loadedAttemptID
                let expectedEmbedURL = loadedEmbedURL
                let expectedDocumentID = playbackDocumentID
                webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self else { return }
                    // A provider manifest must not gain access to cookies from
                    // unrelated pages in the shared WebKit store. Preserve full
                    // scope metadata for final path/expiry checks by the relay.
                    let selectedCookies = cookies.filter { cookie in
                        guard let host = url.host?.lowercased() else { return false }
                        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                        return host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix(".\(domain)"))
                    }
                    var headers: [String: String] = [:]
                    if !referer.isEmpty { headers["Referer"] = referer }
                    if let origin = Self.originString(for: pageURL) { headers["Origin"] = origin }
                    if let userAgent, !userAgent.isEmpty { headers["User-Agent"] = userAgent }
                    let candidate = NativeWebPlaybackCandidate(url: url, headers: headers, cookies: selectedCookies)
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.loadedAttemptID == expectedAttemptID,
                              self.loadedEmbedURL == expectedEmbedURL,
                              self.playbackDocumentID == expectedDocumentID,
                              self.lastNativeCandidateURL == url,
                              self.hasReportedPlayback else { return }
                        self.onNativeCandidateDiscovered?(candidate)
                    }
                }
            default:
                break
            }
        }

        private static func originString(for url: URL?) -> String? {
            guard let url, let scheme = url.scheme, let host = url.host else { return nil }
            if let port = url.port { return "\(scheme)://\(host):\(port)" }
            return "\(scheme)://\(host)"
        }

        private func reportFailure(_ reason: String) {
            guard !hasReportedFailure, !lastSuspended, !isTransportPaused else { return }
            hasReportedFailure = true
            pendingFailureTask?.cancel()
            pendingFailureTask = nil
            startupFailureTask?.cancel()
            startupFailureTask = nil
            FottyLogger.shared.info(
                category: "WebEmbed",
                "Web embed playback failed: \(reason)"
            )
            // WebKit delegates and recovery timers already run on the main
            // thread. Preserve event order and do not queue a stale failure
            // behind a recovery or a newly selected source attempt.
            onPlaybackStalled?(reason)
        }

        private var isCurrentDocument: Bool {
            Self.sameDocumentURL(committedDocumentURL, webView?.url)
        }

        static func sameDocumentURL(_ lhs: URL?, _ rhs: URL?) -> Bool {
            guard let lhs, let rhs else { return false }
            // Delivery queries and ports distinguish sources. Only the fragment
            // is local document state and may change without replacing playback.
            return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
                && lhs.host?.lowercased() == rhs.host?.lowercased()
                && lhs.port == rhs.port && lhs.path == rhs.path && lhs.query == rhs.query
        }

        private let blockedHostFragments = [
            "doubleclick",
            "googlesyndication",
            "adservice",
            "adnxs",
            "exoclick",
            "popads",
            "popcash",
            "propellerads",
            "onclicka",
            "trafficjunky",
            "histats",
            "cdn-lab.shop",
            "llvpn",
            "ndcertainlywhen.com",
            "tanktds.com",
            "stuins.com",
            "my.rtmark.net",
            "luugy.com"
        ]

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let navigation, !retiredNavigations.contains(navigation) else { return }
            let replacesCommittedDocument = hasCommittedSelectedLoad
            if !ownsNavigation(navigation) {
                // A ticket has no WKNavigation identity until didStart. While
                // the selected load is provisional, an unknown late navigation
                // from the previous document must not steal that ticket. HTTP
                // redirects remain part of the load-returned WKNavigation.
                guard hasCommittedSelectedLoad,
                      admittedNavigationGeneration == loadingGeneration else { return }
                if let activeNavigation { retiredNavigations.add(activeNavigation) }
                activeNavigation = navigation
            }
            invalidateNativeTransferSuspension()
            webAudioRevocationRequest = nil
            if replacesCommittedDocument { desiredWebAudioRevocation = nil }
            admittedNavigationGeneration = nil
            isAcceptingMessages = false
            committedDocumentURL = nil
            if isPictureInPictureActive {
                isPictureInPictureActive = false
                onPictureInPictureActiveChanged?(false)
            }
            if hasReportedPlayback {
                // Provider-initiated approved document replacement remains the
                // same selected source, but must prove a new decoded owner.
                hasReportedPlayback = false
                playbackDocumentID = nil
                lastNativeCandidateURL = nil
                hasReportedFailure = false
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                loadStartedAt = Date()
                armStartupDeadline()
            }
            MediaAudioSession.configureForPlaybackIfNeeded()
        }

        @discardableResult
        func admitMainNavigationRequest(_ url: URL) -> Bool {
            guard !shouldBlock(url), shouldAllowTopNavigation(url) else { return false }
            admittedNavigationGeneration = loadingGeneration
            return true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard ownsNavigation(navigation), let url = webView.url else { return }
            acceptCommittedDocument(url)
        }

        @discardableResult
        func acceptCommittedDocument(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https", !shouldBlock(url),
                  shouldAllowTopNavigation(url) else { return false }
            committedDocumentURL = url
            hasCommittedSelectedLoad = true
            isAcceptingMessages = true
            return true
        }

        private func ownsNavigation(_ navigation: WKNavigation?) -> Bool {
            guard let navigation, let activeNavigation else { return false }
            return navigation === activeNavigation
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard ownsNavigation(navigation), !Self.isCancelledNavigation(error) else { return }
            reportDiagnosticStage(.documentFailure, errorCode: (error as NSError).code)
            reportDocumentFailure("Web document failed to load (error code \((error as NSError).code))")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard ownsNavigation(navigation), !Self.isCancelledNavigation(error) else { return }
            reportDiagnosticStage(.documentFailure, errorCode: (error as NSError).code)
            reportDocumentFailure("Web document navigation failed (error code \((error as NSError).code))")
        }

        private static func isCancelledNavigation(_ error: Error) -> Bool {
            let error = error as NSError
            return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard self.webView === webView, loadedAttemptID != nil else { return }
            invalidateNativeTransferSuspension()
            webAudioRevocationRequest = nil
            desiredWebAudioRevocation = nil
            reportDiagnosticStage(.processTerminated)
            isAcceptingMessages = false
            if isPictureInPictureActive {
                isPictureInPictureActive = false
                onPictureInPictureActiveChanged?(false)
            }
            reportDocumentFailure("Web player process ended unexpectedly")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if ownsNavigation(navigation) { reportDiagnosticStage(.documentLoaded) }
            MediaAudioSession.configureForPlaybackIfNeeded()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Provider popups never replace or escape the in-app player.
            nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if shouldBlock(url) || navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame?.isMainFrame == true {
                if navigationAction.navigationType == .linkActivated
                    || navigationAction.navigationType == .formSubmitted {
                    decisionHandler(.cancel)
                    return
                }
                // Keep the player on a known provider origin. User-triggered
                // links must not replace the stream with a provider or ad page.
                decisionHandler(admitMainNavigationRequest(url) ? .allow : .cancel)
                return
            }

            // Browser parity for nested player/media frames: allow arbitrary
            // HTTPS origins except the narrow nuisance denylist. Provider CDNs
            // rotate too often for a static allowlist to be reliable.
            decisionHandler(shouldAllowFrameNavigation(url) ? .allow : .cancel)
        }

        private func shouldAllowTopNavigation(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data"].contains(scheme) { return true }
            guard scheme == "https", let host = url.host?.lowercased() else { return false }
            if let expectedHost = loadedEmbedURL?.host?.lowercased(),
               host == expectedHost || host.hasSuffix(".\(expectedHost)") {
                return true
            }
            return StreamPluginProviderMatching.isApprovedSharedPlaybackHost(host)
        }

        private func shouldAllowFrameNavigation(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data"].contains(scheme) { return true }
            guard scheme == "https", let host = url.host?.lowercased(), !shouldBlock(url) else {
                return false
            }
            if let expectedHost = loadedEmbedURL?.host?.lowercased(),
               host == expectedHost || host.hasSuffix(".\(expectedHost)") {
                return true
            }
            return StreamPluginProviderMatching.isApprovedSharedPlaybackHost(host)
        }

        private func shouldBlock(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            if path.contains("/ad.html") || path.contains("/vast") { return true }
            return blockedHostFragments.contains { host.contains($0) }
        }
    }
}
#else
/// Simulator placeholder — actual provider embeds are validated on physical iOS
/// devices and by the browser playback-matrix tool.
struct LiveWebEmbedPlayerView: View {
    let url: URL
    let referer: String
    let isMuted: Bool
    let isSuspended: Bool
    let attemptID: UUID
    var onPlaybackStarted: ((Int) -> Void)? = nil
    var onPlaybackStalled: ((String) -> Void)? = nil
    var onPlaybackRecovered: (() -> Void)? = nil
    var onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Web embeds are not\navailable in the Simulator")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
#endif
