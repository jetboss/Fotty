import Foundation
#if !targetEnvironment(simulator)
import WebKit

// MARK: - WebView-Based Stream Processor
// Loads embed pages in a headless WKWebView and intercepts .m3u8 network requests.
// This handles JS-obfuscated players that can't be solved with pure HTTP scraping.
// NOTE: WebKit is disabled in the iOS Simulator to prevent an EXC_GUARD/XPC crash
// (macOS Sequoia + iOS sim incompatibility with WebKit's XPC Web Content process).

#if !targetEnvironment(simulator)
@MainActor
class WebViewRenderer: NSObject {
    
    private var webView: WKWebView?
    private var interceptedURLs: [URL] = []
    private var continuation: CheckedContinuation<[StreamSource], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var currentProviderName = ""
    private var currentReferer = ""
    private var currentEmbedURL = ""
    
    private var currentOrigin: String {
        guard let url = URL(string: currentReferer),
              let scheme = url.scheme,
              let host = url.host else {
            return StringObfuscator.decode([0x2E, 0x1B, 0x0, 0x4, 0xA, 0x7B, 0x41, 0x4E, 0x1F, 0x1A, 0x6, 0x8, 0x13, 0x16, 0x24, 0x1C, 0x36, 0x6, 0xC, 0x11, 0x15, 0x6C, 0x7, 0xF, 0x1A, 0x16, 0x1D, 0xA, 0x6, 0x5D, 0x35, 0x5D, 0x2B])
        }
        return "\(scheme)://\(host)"
    }
    
    override init() {
        super.init()
    }
    
    func extractSources(
        from embedURL: String,
        referer: String,
        providerName: String,
        timeout: TimeInterval = 15
    ) async throws -> [StreamSource] {
        
        // Clean up any previous state
        cleanup()
        currentProviderName = providerName
        currentReferer = referer
        currentEmbedURL = embedURL
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.interceptedURLs = []
                
                // Configure WKWebView with script message handler
                let config = WKWebViewConfiguration()
                config.allowsInlineMediaPlayback = true
                config.mediaTypesRequiringUserActionForPlayback = []
                
                let popupGuard = WKUserScript(
                    source: """
                    (function() {
                        try { window.open = function() { return null; }; } catch (e) {}
                        function removeNoise() {
                            try {
                                document.querySelectorAll('iframe').forEach(function(frame) {
                                    var src = (frame.getAttribute('src') || '').toLowerCase();
                                    var tiny = Number(frame.getAttribute('width')) <= 2 && Number(frame.getAttribute('height')) <= 2;
                                    if (frame.id === 'close' || tiny || src.indexOf('/ad.html') !== -1) {
                                        frame.remove();
                                    }
                                });
                            } catch (e) {}
                        }
                        document.addEventListener('DOMContentLoaded', removeNoise);
                        setInterval(removeNoise, 1000);
                    })();
                    """,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
                config.userContentController.addUserScript(popupGuard)

                // Inject script to intercept network requests
                let script = WKUserScript(
                    source: interceptScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
                config.userContentController.addUserScript(script)
                config.userContentController.add(self, name: "streamInterceptor")
                
                // Keep a realistic viewport so player UI gates are not skipped by tiny layouts.
                let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
                webView.navigationDelegate = self
                webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
                // Ensure background embedded players do not blast audio over the native player
                Task {
                    try? await webView.evaluateJavaScript("Object.defineProperty(HTMLMediaElement.prototype, 'muted', { get: () => true, set: () => {} });")
                }
                self.webView = webView
                
                // Load the embed page
                guard let url = URL(string: embedURL) else {
                    continuation.resume(throwing: ProcessorError.invalidURL)
                    self.continuation = nil
                    return
                }
                
                // WKWebView strips custom Referer on direct loads. Host-frame the embed
                // under the site origin (same pattern Safari / LiveWebEmbedPlayerView use).
                if let host = url.host?.lowercased(),
                   host.contains("embed.st") || host.contains("embedsports"),
                   let base = URL(string: referer) ?? URL(string: "https://www.streamex.net/") {
                    let src = url.absoluteString
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                    let html = """
                    <!DOCTYPE html><html><body style="margin:0;background:#000">
                    <iframe id="fotty-player" src="\(src)" style="position:fixed;inset:0;width:100%;height:100%;border:0"
                      allow="autoplay; encrypted-media; fullscreen" allowfullscreen></iframe>
                    </body></html>
                    """
                    webView.loadHTMLString(html, baseURL: base)
                } else {
                    var request = URLRequest(url: url)
                    request.setValue(referer, forHTTPHeaderField: "Referer")
                    webView.load(request)
                }
                
                // Set timeout
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard let self = self, self.continuation != nil else { return }
                    
                    let sources = self.interceptedURLs.map { url in
                        StreamSource(
                            url: url,
                            quality: "auto",
                            provider: self.currentProviderName,
                            subtitles: [],
                            headers: self.playbackHeaders(for: url)
                        )
                    }
                    
                    self.continuation?.resume(returning: sources)
                    self.continuation = nil
                    self.cleanup()
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cleanup()
            }
        }
    }
    
    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        interceptedURLs = []
        currentEmbedURL = ""
        currentReferer = ""
        currentProviderName = ""
        
        if let cont = continuation {
            cont.resume(throwing: ProcessorError.timeout)
            continuation = nil
        }
    }
    
    // JavaScript that intercepts XHR, fetch, and response bodies to find .m3u8 URLs
    private var interceptScript: String {
        """
        (function() {
            function sendURL(url) {
                if (!url || typeof url !== 'string') return;
                try {
                    var absUrl = new URL(url, window.location.href).href;
                    if (absUrl.startsWith('blob:')) return;
                    
                    // BROADER PATTERN MATCHING: Catch dynamic and obfuscated stream links
                    var isStream = absUrl.includes('.m3u8') || 
                                   absUrl.includes('.mp4') || 
                                   absUrl.includes('playlist') ||
                                   absUrl.includes('master.m3u8');
                                   
                    if (isStream) {
                        window.webkit.messageHandlers.streamInterceptor.postMessage({type: 'url', url: absUrl});
                    }
                } catch(e) {}
            }
            
            function scanJSON(obj, depth) {
                if (depth > 8 || !obj) return;
                if (typeof obj === 'string') {
                    sendURL(obj);
                } else if (typeof obj === 'object') {
                    for (var key in obj) {
                        try { scanJSON(obj[key], depth + 1); } catch(e) {}
                    }
                }
            }
            
            // Intercept fetch - capture RESPONSE BODY
            const origFetch = window.fetch;
            window.fetch = function(url, options) {
                const urlStr = typeof url === 'string' ? url : (url?.url || '');
                sendURL(urlStr);
                return origFetch.apply(this, arguments).then(function(response) {
                    const clone = response.clone();
                    clone.text().then(function(text) {
                        try {
                            const json = JSON.parse(text);
                            scanJSON(json, 0);
                        } catch(e) {
                            if (text.includes('#EXTM3U')) {
                                sendURL(urlStr);
                            }
                        }
                    }).catch(function(){});
                    return response;
                });
            };
            
            // Intercept XHR
            const origOpen = XMLHttpRequest.prototype.open;
            const origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
                this._fottyURL = url ? url.toString() : '';
                sendURL(this._fottyURL);
                return origOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                this.addEventListener('load', function() {
                    try {
                        const json = JSON.parse(this.responseText);
                        scanJSON(json, 0);
                    } catch(e) {}
                });
                return origSend.apply(this, arguments);
            };
            
            function dispatchTap(el) {
                if (!el) return;
                try {
                    ['pointerdown', 'mousedown', 'touchstart', 'pointerup', 'mouseup', 'touchend', 'click'].forEach(function(evtName) {
                        try { el.dispatchEvent(new Event(evtName, { bubbles: true, cancelable: true })); } catch(e) {}
                    });
                    if (typeof el.click === 'function') el.click();
                } catch (e) {}
            }

            // VIDEO TAG SNIFFER: The ultimate hand-off. 
            // If the web player finds the movie (duration > 0), we rip the source and go native.
            setInterval(function() {
                try {
                    const videos = document.querySelectorAll('video');
                    videos.forEach(function(v) {
                        if (v.currentSrc && v.currentSrc.startsWith('http')) {
                            // If it has duration, it's a confirmed valid stream
                            if (v.duration > 0 || v.readyState >= 1) {
                                window.webkit.messageHandlers.streamInterceptor.postMessage({
                                    type: 'url', 
                                    url: v.currentSrc,
                                    isDirect: true,
                                    cookie: document.cookie,
                                    referer: window.location.href
                                });
                            }
                        }
                    });
                } catch(e) {}
            }, 1000);

            // AGGRESSIVE AUTO-CLICKER: Bypasses server-selection walls (VID 1, Server 1, etc.)
            var clickerInterval = setInterval(function() {
                const v = document.querySelector('video');
                
                // QUIESCENCE: Stop clicking immediately if playback has actually started
                if (v && v.duration > 0 && !v.paused) {
                    clearInterval(clickerInterval);
                    return;
                }

                // 1. Selector-based matching
                const selectors = [
                    '.vjs-big-play-button', '.plyr__control--overlaid',
                    'button[title="Play"]', '.play-button', '#play-button',
                    '#pl_but', '#pl_but_background', '[aria-label="Play"]',
                    '.server-item', '.btn-server', '.server', '.jw-display-icon-display'
                ];

                selectors.forEach(function(sel) {
                    try {
                        document.querySelectorAll(sel).forEach(function(btn) {
                            dispatchTap(btn);
                        });
                    } catch (e) {}
                });

                // 2. TEXT-BASED MATCHING: Specifically targets "VID 1", "Server 1", etc.
                try {
                    const allButtons = document.querySelectorAll('button, a, div, span');
                    allButtons.forEach(function(el) {
                        const text = (el.innerText || '').toUpperCase();
                        const targets = ['VID 1', 'SERVER 1', 'WATCH NOW', 'DOWNLOAD', 'CLICK TO PLAY'];
                        if (targets.some(t => text.includes(t))) {
                            dispatchTap(el);
                        }
                    });
                } catch (e) {}

                // 3. Blind center-tap
                try {
                    if (!v || v.paused) {
                        const centerElem = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
                        dispatchTap(centerElem);
                    }
                } catch (e) {}
            }, 800);
            
        })();
        """
    }

    private func playbackHeaders(for streamURL: URL) -> [String: String] {
        let playbackReferer = webView?.url?.absoluteString ?? currentEmbedURL
        let originSource = webView?.url ?? URL(string: currentEmbedURL)
        let playbackOrigin = originString(for: originSource) ?? currentOrigin

        var headers: [String: String] = [
            "Referer": playbackReferer,
            "Origin": playbackOrigin,
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
        ]

        if let cookies = HTTPCookieStorage.shared.cookies(for: streamURL), !cookies.isEmpty {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            if let cookie = cookieHeaders["Cookie"], !cookie.isEmpty {
                headers["Cookie"] = cookie
            }
        }

        return headers
    }

    private func originString(for url: URL?) -> String? {
        guard let url,
              let scheme = url.scheme,
              let host = url.host else {
            return nil
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewRenderer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }
        
        print("[WebViewRenderer] Intercepted: \(urlString)")
        
        if !interceptedURLs.contains(url) {
            interceptedURLs.append(url)
            
            // Resolve immediately if we found an .m3u8 OR it's a direct video-tag rip
            let isDirect = body["isDirect"] as? Bool ?? false
            if urlString.contains(".m3u8") || isDirect {
                Task {
                    if let store = self.webView?.configuration.websiteDataStore.httpCookieStore {
                        let cookies = await store.allCookies()
                        for cookie in cookies {
                            HTTPCookieStorage.shared.setCookie(cookie)
                        }
                    }
                    
                    let sources = self.interceptedURLs.map { interceptedURL in
                        StreamSource(
                            url: interceptedURL,
                            quality: "auto",
                            provider: self.currentProviderName,
                            subtitles: [],
                            headers: self.playbackHeaders(for: interceptedURL),
                            cookie: body["cookie"] as? String,
                            referer: body["referer"] as? String
                        )
                    }
                    
                    if let wv = self.webView {
                        Task {
                            try? await wv.evaluateJavaScript("document.querySelectorAll('video, audio').forEach(v => { v.muted = true; v.volume = 0; });")
                        }
                        ActiveWebViewManager.keepAlive(wv)
                    }
                    
                    self.continuation?.resume(returning: sources)
                    self.continuation = nil
                    
                    self.timeoutTask?.cancel()
                    self.timeoutTask = nil
                    self.webView?.configuration.userContentController.removeAllScriptMessageHandlers()
                    self.webView = nil
                    self.interceptedURLs = []
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let autoplayKick = """
        (function() {
            var kickCount = 0;
            var kicker = setInterval(function() {
                kickCount++;
                if (kickCount > 15) { clearInterval(kicker); return; }
                
                var selectors = [
                    '#pl_but', '#pl_but_background', '.vjs-big-play-button', 
                    '.plyr__control--overlaid', '.jw-display-icon-display', 
                    '.jw-icon-display', '[aria-label="Play"]'
                ];
                selectors.forEach(function(sel) {
                    try {
                        document.querySelectorAll(sel).forEach(function(node) {
                            if (node && (node.offsetWidth > 0 || node.offsetHeight > 0)) {
                                node.click();
                                // Also dispatch manual events in case .click() is gated
                                node.dispatchEvent(new MouseEvent('mousedown', {bubbles:true}));
                                node.dispatchEvent(new MouseEvent('mouseup', {bubbles:true}));
                                node.dispatchEvent(new MouseEvent('click', {bubbles:true}));
                            }
                        });
                    } catch (e) {}
                });
            }, 500);
        })();
        """
        Task {
            try? await webView.evaluateJavaScript(autoplayKick)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            
            // Intercept .m3u8 requests at the navigation level
            if urlString.contains(".m3u8") || urlString.contains(".mp4") {
                print("[WebViewRenderer] Navigation intercepted: \(urlString)")
                if !interceptedURLs.contains(url) {
                    interceptedURLs.append(url)
                }
            }
            
            // Block known ad domains
            let adDomains = [
                "doubleclick",
                "googlesyndication",
                "adservice",
                "cdn-lab.shop",
                "llvpn",
                "ads.",
                "tracker."
            ]
            if adDomains.contains(where: { urlString.contains($0) }) {
                decisionHandler(.cancel)
                return
            }
        }
        
        decisionHandler(.allow)
    }
}

@MainActor
class ActiveWebViewManager {
    static var activeWebViews: [WKWebView] = []
    
    static func keepAlive(_ webView: WKWebView) {
        activeWebViews.append(webView)
    }
    
    static func clear() {
        activeWebViews.forEach { $0.stopLoading() }
        activeWebViews.removeAll()
    }
}
#else
// MARK: - Simulator Stubs
// WebKit's XPC Web Content process causes an EXC_GUARD crash in the simulator.
// These stubs provide the same API surface with no-op implementations.

@MainActor
final class WebViewRenderer {
    init() {}

    func extractSources(
        from embedURL: String,
        referer: String,
        providerName: String,
        timeout: TimeInterval = 15
    ) async throws -> [StreamSource] {
        return []
    }
}

@MainActor
final class ActiveWebViewManager {
    static func keepAlive(_ view: AnyObject) {}
    static func clear() {}
}
#endif

#endif
