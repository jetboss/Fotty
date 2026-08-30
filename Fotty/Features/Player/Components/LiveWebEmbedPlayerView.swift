import SwiftUI
import WebKit

enum LivePlaybackPolicy {
    /// Provider embeds can spend several seconds negotiating a manifest after
    /// the document and player chrome have loaded. The old 10-second cutoff
    /// abandoned sources which then worked after a manual retry.
    static let webStartupFailureSeconds: TimeInterval = 20

    /// A decoded web stream gets a generous recovery window before Fotty
    /// abandons it. Short network interruptions should preserve the source.
    static let webStallFailureSeconds: TimeInterval = 30
    static let webRecoveryGraceSeconds: TimeInterval = 8
    static let webControlAutoHideSeconds: TimeInterval = 4

    static func isExplicitProviderRejection(_ reason: String) -> Bool {
        let normalized = reason.lowercased()
        return normalized.contains("embedding disabled")
            || normalized.contains("broadcast is unavailable")
            || normalized.contains("channel is unavailable")
            || normalized.contains("stream is unavailable")
    }

    /// Child-frame players can emit opaque errors before the real broadcast
    /// has finished negotiating. We deliberately wait out the complete startup
    /// window; if no decoded progress arrives, that elapsed deadline—not the
    /// opaque child-frame wording—is the truthful terminal boundary.
    static func deferredStartupFailureReason(_ providerReason: String) -> String {
        guard !isExplicitProviderRejection(providerReason) else { return providerReason }
        return "Startup timeout: no decoded video within \(Int(webStartupFailureSeconds)) seconds"
    }
}

struct WebPlaybackCommand: Equatable {
    let id: UUID
    let shouldPlay: Bool
}

enum WebPlaybackTransportState: String {
    case playing, paused
}

struct NativeWebPlaybackCandidate: Equatable {
    let url: URL
    let headers: [String: String]
}

#if !targetEnvironment(simulator)
struct LiveWebEmbedPlayerView: UIViewRepresentable {
    let url: URL
    let referer: String
    let isMuted: Bool
    let isSuspended: Bool
    /// The standard player must leave the provider's play, pause, and unmute
    /// controls alone. MultiView opts into Fotty-controlled audio focus.
    var providerControlsAudio = false
    let attemptID: UUID
    var playbackCommand: WebPlaybackCommand? = nil
    var onSurfaceTapped: (() -> Void)? = nil
    var onTransportStateChanged: ((WebPlaybackTransportState) -> Void)? = nil
    var onPlaybackStarted: ((Int) -> Void)? = nil
    var onPlaybackStalled: ((String) -> Void)? = nil
    var onPlaybackRecovered: (() -> Void)? = nil
    var onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSurfaceTapped: onSurfaceTapped,
            onTransportStateChanged: onTransportStateChanged,
            onPlaybackStarted: onPlaybackStarted,
            onPlaybackStalled: onPlaybackStalled,
            onPlaybackRecovered: onPlaybackRecovered,
            onNativeCandidateDiscovered: onNativeCandidateDiscovered
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
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.playbackMonitorScript(
                    isMuted: isMuted,
                    providerControlsAudio: providerControlsAudio,
                    isSuspended: isSuspended
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
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
        context.coordinator.lastPlaybackCommandID = playbackCommand?.id
        load(url: url, referer: referer, attemptID: attemptID, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSurfaceTapped = onSurfaceTapped
        context.coordinator.onTransportStateChanged = onTransportStateChanged
        context.coordinator.onPlaybackStarted = onPlaybackStarted
        context.coordinator.onPlaybackStalled = onPlaybackStalled
        context.coordinator.onPlaybackRecovered = onPlaybackRecovered
        context.coordinator.onNativeCandidateDiscovered = onNativeCandidateDiscovered

        if context.coordinator.loadedEmbedURL != url
            || context.coordinator.loadedAttemptID != attemptID {
            context.coordinator.loadedEmbedURL = url
            context.coordinator.loadedAttemptID = attemptID
            load(url: url, referer: referer, attemptID: attemptID, in: webView, coordinator: context.coordinator)
        }
        if context.coordinator.lastMuted != isMuted {
            context.coordinator.lastMuted = isMuted
            applyMutedState(in: webView)
        }
        if context.coordinator.lastSuspended != isSuspended {
            context.coordinator.lastSuspended = isSuspended
            applySuspendedState(in: webView)
        }
        if let playbackCommand,
           context.coordinator.lastPlaybackCommandID != playbackCommand.id {
            context.coordinator.lastPlaybackCommandID = playbackCommand.id
            applyPlaybackCommand(playbackCommand, in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript(
            "document.querySelectorAll('video, audio').forEach(function(media){try{media.pause();}catch(e){}});"
        )
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "fottyPlayerBridge")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.webView = nil
        coordinator.pendingFailureTask?.cancel()
        coordinator.pendingFailureTask = nil
    }

    private func load(
        url: URL,
        referer: String,
        attemptID: UUID,
        in webView: WKWebView,
        coordinator: Coordinator
    ) {
        MediaAudioSession.configureForPlaybackIfNeeded()
        coordinator.loadedEmbedURL = url
        coordinator.loadedAttemptID = attemptID
        coordinator.lastReferer = referer
        coordinator.loadStartedAt = Date()
        coordinator.hasReportedFailure = false
        coordinator.hasReportedPlayback = false
        coordinator.playbackDocumentID = nil
        coordinator.isAcceptingMessages = false
        coordinator.lastNativeCandidateURL = nil
        coordinator.pendingFailureTask?.cancel()
        coordinator.pendingFailureTask = nil

        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 15
        if !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        // Leave User-Agent untouched so WKWebView presents its real iPad/iPhone
        // browser identity. A hard-coded desktop UA caused provider divergence.
        webView.load(request)
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
                    }
                    document.querySelectorAll('iframe').forEach(function(frame) {
                        try {
                            if (frame.contentWindow) {
                                frame.contentWindow.postMessage({ type: 'fotty_set_muted', muted: muted }, '*');
                            }
                        } catch (e) {}
                    });
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
        isSuspended: Bool
    ) -> String {
        """
        (function() {
            if (window.__fottyPlaybackMonitorInstalled) return;
            window.__fottyPlaybackMonitorInstalled = true;

            var playbackConfirmed = false;
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
            var resumeAfterSuspend = false;
            var latestNativeCandidate = '';
            var lastReportedNativeCandidate = '';

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
                return normalized.indexOf('vpn recommended') !== -1
                    && normalized.indexOf('install') !== -1
                    && normalized.indexOf('continue watching') !== -1;
            }

            function removeKnownNuisanceSolicitations() {
                try {
                    if (!document.body || typeof document.createTreeWalker !== 'function') return;
                    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                    var matches = [];
                    var textNode;
                    while ((textNode = walker.nextNode())) {
                        var nodeText = (textNode.nodeValue || '').toLowerCase();
                        if (nodeText.indexOf('vpn recommended') === -1) continue;

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

            // Reject only the reproduced install solicitation when a provider
            // renders it through JavaScript alert/confirm instead of HTML.
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

            function post(type, reason) {
                try {
                    var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.fottyPlayerBridge;
                    if (bridge) bridge.postMessage({ type: type, reason: reason || '', pageURL: location.href, documentID: playbackDocumentID });
                } catch (e) {}
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
                    var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.fottyPlayerBridge;
                    if (bridge) {
                        bridge.postMessage({
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
                if (!candidate) return;
                latestNativeCandidate = candidate;
                reportNativeCandidateIfReady();
            }

            try {
                var originalFetch = window.fetch;
                if (typeof originalFetch === 'function') {
                    window.fetch = function(input) {
                        try { rememberNativeCandidate(typeof input === 'string' ? input : (input && input.url)); } catch (e) {}
                        return originalFetch.apply(this, arguments);
                    };
                }
            } catch (e) {}

            try {
                var originalOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, requestURL) {
                    try { rememberNativeCandidate(requestURL && requestURL.toString()); } catch (e) {}
                    return originalOpen.apply(this, arguments);
                };
            } catch (e) {}

            function videos() {
                try { return Array.prototype.slice.call(document.querySelectorAll('video')); }
                catch (e) { return []; }
            }

            function mediaElements() {
                try { return Array.prototype.slice.call(document.querySelectorAll('video, audio')); }
                catch (e) { return []; }
            }

            window.__fottySetPlaybackSuspended = function(suspended) {
                playbackSuspended = !!suspended;
                var media = mediaElements();
                if (playbackSuspended) {
                    if (media.some(function(item) { return !item.paused && !item.ended; })) {
                        resumeAfterSuspend = true;
                    }
                    media.forEach(function(item) {
                        try { item.pause(); } catch (e) {}
                    });
                    try {
                        var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                        var state = jw && typeof jw.getState === 'function' ? jw.getState() : null;
                        if (state === 'playing' || state === 'buffering') resumeAfterSuspend = true;
                        if (jw && typeof jw.pause === 'function') jw.pause(true);
                    } catch (e) {}
                } else if (resumeAfterSuspend) {
                    resumeAfterSuspend = false;
                    media.forEach(function(item) {
                        try {
                            var promise = item.play && item.play();
                            if (promise && promise.catch) promise.catch(function() {});
                        } catch (e) {}
                    });
                    try {
                        var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                        if (jw && typeof jw.play === 'function') jw.play();
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
                // A rejected play request must restore the truthful paused UI.
                function reportCommandResult() {
                    reportTransportState(playbackVideo, true);
                }
                mediaElements().forEach(function(item) {
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
                    if (jw) {
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
                videos().forEach(function(video) {
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

            window.addEventListener('message', function(event) {
                var data = event && event.data;
                if (!data) return;
                if (data.type === 'fotty_set_muted') {
                    window.__fottySetMuted(!!data.muted);
                } else if (data.type === 'fotty_set_suspended') {
                    window.__fottySetPlaybackSuspended(!!data.suspended);
                } else if (data.type === 'fotty_set_playing') {
                    window.__fottySetPlaying(!!data.shouldPlay);
                }
            });

            function isDecoded(video) {
                return video && video.readyState >= 2 && video.videoWidth >= 16 && video.videoHeight >= 16;
            }

            function reportTransportState(video, force) {
                if (!playbackConfirmed || video !== playbackVideo || !video
                    || playbackSuspended || document.hidden || video.ended) return;
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
                if (playbackSuspended) return;
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
                if (video.currentSrc) rememberNativeCandidate(video.currentSrc);
                if (video.currentTime > lastProgressTime + 0.1) {
                    lastProgressTime = video.currentTime;
                    lastProgressAt = Date.now();
                    if (stallNoticeSent || failureReported) {
                        stallNoticeSent = false;
                        failureReported = false;
                        post('playback_recovered');
                    }
                    if (!playbackConfirmed && video.currentTime > 0.25 && !video.paused && !video.ended) {
                        playbackConfirmed = true;
                        playbackVideo = video;
                        post('playback_started');
                        reportNativeCandidateIfReady();
                    }
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
            document.addEventListener('error', function(event) {
                var video = event.target;
                if (video && video.tagName === 'VIDEO'
                    && (playbackConfirmed ? video === playbackVideo : videos().indexOf(video) !== -1)) {
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
            try {
                var nuisanceObserver = new MutationObserver(removeNuisanceElements);
                nuisanceObserver.observe(document.documentElement, { childList: true, subtree: true });
            } catch (e) {}

            // Browser-parity first: let the provider initialize untouched. If it
            // has not started after 3.5 seconds, perform one restrained play kick.
            setTimeout(function() {
                if (playbackConfirmed || document.hidden) return;
                var allVideos = videos();
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
                    var element = document.querySelector('.jw-error-msg, .jw-error, .jw-media-error, .vjs-error-display');
                    var ownsPlayer = videos().length > 0 || typeof window.jwplayer === 'function';
                    if (ownsPlayer && element && element.textContent && element.textContent.trim()) {
                        reportFailure(element.textContent.trim());
                        return;
                    }
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
                if (playbackSuspended) {
                    mediaElements().forEach(function(media) {
                        try { media.pause(); } catch (e) {}
                    });
                    return;
                }
                synchronizeMuteState();
                videos().forEach(inspectProgress);
                try {
                    performance.getEntriesByType('resource').forEach(function(entry) {
                        rememberNativeCandidate(entry && entry.name);
                    });
                } catch (e) {}
                try {
                    var jw = window.jwplayer && (window.jwplayer('player') || window.jwplayer());
                    var item = jw && typeof jw.getPlaylistItem === 'function' ? jw.getPlaylistItem() : null;
                    if (item) {
                        rememberNativeCandidate(item.file);
                        (item.sources || []).forEach(function(source) { rememberNativeCandidate(source && source.file); });
                    }
                } catch (e) {}
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
                if (!playbackConfirmed || playbackSuspended || document.hidden) return;
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
        var lastPlaybackCommandID: UUID?
        var loadStartedAt = Date()
        var hasReportedFailure = false
        var hasReportedPlayback = false
        var playbackDocumentID: String?
        var isAcceptingMessages = false
        var pendingFailureTask: DispatchWorkItem?
        var onSurfaceTapped: (() -> Void)?
        var onTransportStateChanged: ((WebPlaybackTransportState) -> Void)?
        var onPlaybackStarted: ((Int) -> Void)?
        var onPlaybackStalled: ((String) -> Void)?
        var onPlaybackRecovered: (() -> Void)?
        var onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)?
        var lastNativeCandidateURL: URL?

        init(
            onSurfaceTapped: (() -> Void)? = nil,
            onTransportStateChanged: ((WebPlaybackTransportState) -> Void)? = nil,
            onPlaybackStarted: ((Int) -> Void)? = nil,
            onPlaybackStalled: ((String) -> Void)? = nil,
            onPlaybackRecovered: (() -> Void)? = nil,
            onNativeCandidateDiscovered: ((NativeWebPlaybackCandidate) -> Void)? = nil
        ) {
            self.onSurfaceTapped = onSurfaceTapped
            self.onTransportStateChanged = onTransportStateChanged
            self.onPlaybackStarted = onPlaybackStarted
            self.onPlaybackStalled = onPlaybackStalled
            self.onPlaybackRecovered = onPlaybackRecovered
            self.onNativeCandidateDiscovered = onNativeCandidateDiscovered
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "fottyPlayerBridge",
                  isAcceptingMessages,
                  isCurrentDocument,
                  let body = message.body as? [String: Any] else { return }
            handlePlaybackMessage(body)
        }

        func handlePlaybackMessage(_ body: [String: Any]) {
            guard let type = body["type"] as? String else { return }
            // Child/ad frames have independent monitors. After decoding starts,
            // only the owning document may fail, recover, or hand off that stream.
            if hasReportedPlayback,
               ["transport_state", "stream_failed", "playback_recovered", "native_candidate"].contains(type) {
                guard let documentID = body["documentID"] as? String,
                      documentID == playbackDocumentID else { return }
            }

            switch type {
            case "surface_tapped":
                onSurfaceTapped?()
            case "playback_started":
                guard !hasReportedPlayback, let documentID = body["documentID"] as? String,
                      !documentID.isEmpty else { return }
                hasReportedPlayback = true
                playbackDocumentID = documentID
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                let latency = max(0, Int(Date().timeIntervalSince(loadStartedAt) * 1_000))
                // Keep start and subsequent transport events in WebKit order.
                onPlaybackStarted?(latency)
            case "transport_state":
                guard hasReportedPlayback,
                      !lastSuspended,
                      let documentID = body["documentID"] as? String,
                      documentID == playbackDocumentID,
                      let rawState = body["reason"] as? String,
                      let state = WebPlaybackTransportState(rawValue: rawState) else { return }
                if state == .paused {
                    pendingFailureTask?.cancel()
                    pendingFailureTask = nil
                    hasReportedFailure = false
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
                        let work = DispatchWorkItem { [weak self] in
                            guard let self,
                                  self.loadedEmbedURL == expectedURL,
                                  self.loadedAttemptID == expectedAttemptID,
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
                    let work = DispatchWorkItem { [weak self] in
                        guard let self,
                              self.loadedEmbedURL == expectedURL,
                              self.loadedAttemptID == expectedAttemptID,
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
                pendingFailureTask?.cancel()
                pendingFailureTask = nil
                hasReportedFailure = false
                onPlaybackRecovered?()
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
                webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self else { return }
                    let matchingCookies = cookies.filter { cookie in
                        guard let host = url.host?.lowercased() else { return false }
                        let domain = cookie.domain
                            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                            .lowercased()
                        return host == domain || host.hasSuffix(".\(domain)")
                    }
                    var headers: [String: String] = [:]
                    if !referer.isEmpty { headers["Referer"] = referer }
                    if let origin = Self.originString(for: pageURL) { headers["Origin"] = origin }
                    if let userAgent, !userAgent.isEmpty { headers["User-Agent"] = userAgent }
                    if let cookie = HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"], !cookie.isEmpty {
                        headers["Cookie"] = cookie
                    }
                    let candidate = NativeWebPlaybackCandidate(url: url, headers: headers)
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.loadedAttemptID == expectedAttemptID,
                              self.loadedEmbedURL == expectedEmbedURL,
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
            guard !hasReportedFailure else { return }
            hasReportedFailure = true
            pendingFailureTask?.cancel()
            pendingFailureTask = nil
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
            guard let expected = loadedEmbedURL, let current = webView?.url else { return false }
            return expected.scheme?.lowercased() == current.scheme?.lowercased()
                && expected.host?.lowercased() == current.host?.lowercased()
                && expected.path == current.path
        }

        private let allowedTopLevelDomains = [
            "embed.st",
            "embedhd.st",
            "exposestrat.com",
            "embedsports.top",
            "streamex.net",
            "streamex.sh",
            "streamed.pk",
            "streamed.su",
            "pooembed.eu",
            "score808live.tv",
            "strmd.st"
        ]

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
            MediaAudioSession.configureForPlaybackIfNeeded()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            isAcceptingMessages = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
                decisionHandler(shouldAllowTopNavigation(url) ? .allow : .cancel)
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
            guard ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return false }
            if let expectedHost = loadedEmbedURL?.host?.lowercased(),
               host == expectedHost || host.hasSuffix(".\(expectedHost)") {
                return true
            }
            return allowedTopLevelDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }
        }

        private func shouldAllowFrameNavigation(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data"].contains(scheme) { return true }
            return ["http", "https"].contains(scheme) && !shouldBlock(url)
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
