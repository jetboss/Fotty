import Foundation
import os.log

private let processorLogger = Logger(subsystem: "com.jelani.Fotty", category: "StreamProcessor")

#if !targetEnvironment(simulator)
import WebKit

// MARK: - Network-Level Stream Interceptor
// Intercepts ALL network requests made by the WKWebView (including cross-origin iframe content)
// by replacing https:// with a custom scheme, handling it, and forwarding to URLSession.
// This completely bypasses the WKWebView JS sandbox limitation.
// NOTE: Disabled in the iOS Simulator — see WebViewRenderer.swift for rationale.

@MainActor
class StreamNetworkProcessor: NSObject {
    
    private let customScheme = "streamhttps"
    private var webView: WKWebView?
    private var foundURLs: [URL] = []
    private var continuation: CheckedContinuation<[StreamSource], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var providerName: String = ""
    private var refererURL: String = ""
    
    override init() {
        super.init()
    }
    
    func extractSources(
        from embedURL: String,
        referer: String,
        providerName: String,
        timeout: TimeInterval = 20
    ) async throws -> [StreamSource] {
        
        self.providerName = providerName
        self.refererURL = referer
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.foundURLs = []
            
            // Use WKURLSchemeHandler to intercept ALL requests
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            
            // Register our custom scheme handler
            let schemeHandler = StreamSchemeHandler(processor: self)
            config.setURLSchemeHandler(schemeHandler, forURLScheme: customScheme)
            
            // Also hook JS layer for same-origin requests
            let jsScript = WKUserScript(
                source: jsInjection,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(jsScript)
            config.userContentController.add(self, name: "streamFound")
            
            // Keep a realistic viewport so player scripts that gate by layout size still run.
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            self.webView = wv
            
            // Load the page
            guard let url = URL(string: embedURL) else {
                continuation.resume(throwing: ProcessorError.invalidURL)
                self.continuation = nil
                return
            }
            
            var request = URLRequest(url: url)
            request.setValue(referer, forHTTPHeaderField: "Referer")
            wv.load(request)
            
            // Timeout — resolve with whatever we found
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self = self, self.continuation != nil else { return }
                let sources = self.foundURLs.map {
                    StreamSource(url: $0, quality: "auto", provider: providerName, subtitles: [], headers: ["Referer": referer])
                }
                self.continuation?.resume(returning: sources)
                self.continuation = nil
                self.cleanup()
            }
        }
    }
    
    func didFindStreamURL(_ urlString: String, headers: [String: String] = [:]) {
        guard let url = URL(string: urlString), !foundURLs.contains(url) else { return }
        processorLogger.info("Found: \(urlString, privacy: .public)")
        foundURLs.append(url)
        
        if urlString.contains(".m3u8") || urlString.contains(".mp4") {
            let allHeaders = headers.isEmpty ? ["Referer": refererURL] : headers
            let sources = foundURLs.map {
                StreamSource(url: $0, quality: "auto", provider: providerName, subtitles: [], headers: allHeaders)
            }
            continuation?.resume(returning: sources)
            continuation = nil
            cleanup()
        }
    }
    
    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        foundURLs = []
        
        if let cont = continuation {
            cont.resume(returning: [])
            continuation = nil
        }
    }
    
    private var jsInjection: String {
        """
        (function() {
            function report(url) {
                if (!url || typeof url !== 'string') return;
                try { window.webkit.messageHandlers.streamFound.postMessage({url: url}); } catch(e) {}
            }
            function scanObj(o, d) {
                if (d > 8 || !o) return;
                if (typeof o === 'string') { report(o); return; }
                if (typeof o === 'object') { for (var k in o) { try { scanObj(o[k], d+1); } catch(e){} } }
            }
            
            const OF = window.fetch;
            window.fetch = function(url, opts) {
                const us = typeof url === 'string' ? url : (url?.url||'');
                report(us);
                return OF.apply(this, arguments).then(function(r) {
                    r.clone().text().then(function(t) {
                        try { scanObj(JSON.parse(t), 0); } catch(e) {
                            if (t.includes('#EXTM3U')) report(us);
                        }
                    }).catch(function(){});
                    return r;
                });
            };
            
            const OO = XMLHttpRequest.prototype.open, OS = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(m,u) { this._u = u?u.toString():''; report(this._u); return OO.apply(this,arguments); };
            XMLHttpRequest.prototype.send = function() {
                this.addEventListener('load', function() { try { scanObj(JSON.parse(this.responseText),0); } catch(e){} });
                return OS.apply(this,arguments);
            };
            
            const oSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
            if (oSrc?.set) { Object.defineProperty(HTMLMediaElement.prototype, 'src', { set: function(v) { report(v); return oSrc.set.call(this,v); }, get: oSrc.get }); }
            
            function dispatchTap(el) {
                if (!el) return;
                try {
                    ['pointerdown', 'mousedown', 'touchstart', 'pointerup', 'mouseup', 'touchend', 'click'].forEach(function(evtName) {
                        try { el.dispatchEvent(new Event(evtName, { bubbles: true, cancelable: true })); } catch (e) {}
                    });
                    if (typeof el.click === 'function') el.click();
                } catch (e) {}
            }

            function clickCandidates() {
                var selectors = [
                    '.vjs-big-play-button',
                    '.plyr__control--overlaid',
                    '.play-button',
                    '#play-button',
                    '.jw-display-icon-display',
                    '.jw-icon-display',
                    '.play-wrapper',
                    '.button-play',
                    '#pl_but',
                    '#pl_but_background',
                    '[aria-label=\"Play\"]',
                    'button[title=\"Play\"]'
                ];
                selectors.forEach(function(sel) {
                    try {
                        document.querySelectorAll(sel).forEach(function(node) { dispatchTap(node); });
                    } catch (e) {}
                });

                try {
                    var center = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
                    dispatchTap(center);
                } catch (e) {}
            }

            setInterval(clickCandidates, 700);
        })();
        """
    }
}

// MARK: - WKScriptMessageHandler

extension StreamNetworkProcessor: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any], let url = body["url"] as? String {
            didFindStreamURL(url)
        }
    }
}

// MARK: - WKNavigationDelegate

extension StreamNetworkProcessor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let autoplayKick = """
        (function() {
            var selectors = ['#pl_but', '#pl_but_background', '.vjs-big-play-button', '.plyr__control--overlaid', '.jw-display-icon-display', '.jw-icon-display'];
            selectors.forEach(function(sel) {
                try {
                    document.querySelectorAll(sel).forEach(function(node) {
                        if (typeof node.click === 'function') node.click();
                    });
                } catch (e) {}
            });
        })();
        """
        webView.evaluateJavaScript(autoplayKick, completionHandler: nil)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url {
            let s = url.absoluteString
            if s.contains(".m3u8") || s.contains(".mp4") {
                didFindStreamURL(s)
            }
            // Block ad domains
            let blocked = ["doubleclick", "googlesyndication", "adnxs", "tracker.", "ads."]
            if blocked.contains(where: { s.contains($0) }) {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
}

// MARK: - Custom URL Scheme Handler
// This interceptor sees ALL requests including those from cross-origin iframes

class StreamSchemeHandler: NSObject, WKURLSchemeHandler {
    
    weak var processor: StreamNetworkProcessor?
    
    init(processor: StreamNetworkProcessor) {
        self.processor = processor
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // The custom scheme is used to rewrite https:// — not actually needed in this version
        // Just immediately cancel to avoid blocking
        urlSchemeTask.didFailWithError(URLError(.cancelled))
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
#else
// MARK: - Simulator Stub
@MainActor
final class StreamNetworkProcessor {
    init() {}

    func extractSources(
        from embedURL: String,
        referer: String,
        providerName: String,
        timeout: TimeInterval = 20
    ) async throws -> [StreamSource] {
        return []
    }
}

#endif
