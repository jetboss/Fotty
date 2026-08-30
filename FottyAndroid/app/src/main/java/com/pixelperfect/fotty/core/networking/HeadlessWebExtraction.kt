package com.pixelperfect.fotty.core.networking

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import com.pixelperfect.fotty.core.network.models.streaming.StreamSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.util.Locale
import kotlin.coroutines.resume

internal object HeadlessWebExtraction {

    private const val USER_AGENT =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private val adHostHints = listOf(
        "doubleclick",
        "googlesyndication",
        "adservice",
        "adnxs",
        "ads.",
        "tracker.",
        "bolsterate.net",
        "ljline.com"
    )

    private val trustedExtractionHosts = setOf(
        "embedsports.top",
        "www.embedsports.top",
        "pooembed.eu",
        "www.pooembed.eu",
        "a.cdn-lab.shop",
        "ann.cdn-lab.shop"
    )

    private val mediaUrlRegex = Regex(
        pattern = """https?://[^\\s\"'<>]+?\\.(m3u8|m3u|mpd|mp4|m4s|ts)(\\?[^\\s\"'<>]*)?""",
        option = RegexOption.IGNORE_CASE
    )

    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    suspend fun extract(
        context: Context,
        embedUrl: String,
        referer: String,
        providerName: String,
        timeoutSeconds: Long,
        resolveOnMp4: Boolean,
        logTag: String
    ): List<StreamSource> = withContext(Dispatchers.Main.immediate) {
        suspendCancellableCoroutine { continuation ->
            val mainHandler = Handler(Looper.getMainLooper())
            val cookieManager = CookieManager.getInstance()
            val found = LinkedHashMap<String, StreamSource>()

            var completed = false
            var webView: WebView? = null

            fun cleanup() {
                val current = webView
                webView = null
                current?.stopLoading()
                current?.removeJavascriptInterface("FottyStreamBridge")
                current?.destroy()
            }

            fun completeNow(result: List<StreamSource>) {
                if (Looper.myLooper() != Looper.getMainLooper()) {
                    mainHandler.post { completeNow(result) }
                    return
                }
                if (completed) return
                completed = true
                cleanup()
                continuation.resume(result)
            }

            fun originFor(refererValue: String): String {
                val lowered = refererValue.trim()
                if (lowered.isBlank()) return "https://embed.wplay.me"
                return try {
                    val uri = java.net.URI(lowered)
                    val scheme = uri.scheme ?: "https"
                    val host = uri.host ?: return "https://embed.wplay.me"
                    "$scheme://$host"
                } catch (_: Exception) {
                    "https://embed.wplay.me"
                }
            }

            fun normalizeUrl(raw: String): String {
                return raw
                    .replace("\\u0026", "&")
                    .replace("&amp;", "&")
                    .replace("&#38;", "&")
                    .trim()
            }

            fun isMediaUrl(url: String): Boolean {
                val lowered = url.lowercase(Locale.US)
                return lowered.contains(".m3u8")
                    || lowered.contains(".m3u")
                    || lowered.contains(".mpd")
                    || lowered.contains(".mp4")
                    || lowered.contains(".m4s")
                    || lowered.contains(".ts?")
                    || lowered.contains(".ts&")
                    || lowered.endsWith(".ts")
                    || lowered.contains("chunklist")
                    || lowered.contains("playlist")
                    || lowered.contains("manifest")
            }

            fun shouldResolveImmediately(url: String): Boolean {
                val lowered = url.lowercase(Locale.US)
                if (lowered.contains(".m3u8")) return true
                if (lowered.contains(".mpd")) return true
                if (lowered.contains("chunklist")) return true
                if (lowered.contains("playlist.m3u8")) return true
                if (lowered.contains("master.m3u8")) return true
                return resolveOnMp4 && lowered.contains(".mp4")
            }

            fun isTrustedHost(host: String): Boolean {
                if (host.isBlank()) return false
                return trustedExtractionHosts.any { trusted ->
                    host == trusted || host.endsWith(".$trusted")
                }
            }

            fun buildStreamHeaders(targetUrl: String): Map<String, String> {
                val baseHeaders = linkedMapOf(
                    "Referer" to referer,
                    "Origin" to originFor(referer),
                    "User-Agent" to USER_AGENT
                )
                val cookie = cookieManager.getCookie(targetUrl)
                if (!cookie.isNullOrBlank()) {
                    baseHeaders["Cookie"] = cookie
                }
                return baseHeaders
            }

            fun captureCandidate(rawCandidate: String?) {
                if (rawCandidate.isNullOrBlank() || completed) return
                val normalized = normalizeUrl(rawCandidate)
                if (normalized.startsWith("blob:", ignoreCase = true)) return

                val extracted = mutableListOf<String>()
                if (normalized.startsWith("http://") || normalized.startsWith("https://")) {
                    extracted += normalized
                }
                extracted += mediaUrlRegex.findAll(normalized).map { normalizeUrl(it.value) }

                for (candidate in extracted.distinct()) {
                    if (!isMediaUrl(candidate)) continue
                    if (found.containsKey(candidate)) continue

                    found[candidate] = StreamSource(
                        id = java.util.UUID.randomUUID().toString(),
                        eventId = "unknown", // Event ID is unknown at this low level
                        url = candidate,
                        provider = providerName,
                        type = com.pixelperfect.fotty.core.network.models.streaming.StreamType.DIRECT,
                        label = providerName,
                        qualityLabel = "auto",
                        headers = buildStreamHeaders(candidate)
                    )

                    if (shouldResolveImmediately(candidate)) {
                        completeNow(found.values.toList())
                        return
                    }
                }
            }

            val bridge = object {
                @JavascriptInterface
                fun report(url: String?) {
                    mainHandler.post {
                        captureCandidate(url)
                    }
                }
            }

            val timeoutRunnable = Runnable {
                if (!completed) {
                    completeNow(found.values.toList())
                }
            }

            val appContext = context.applicationContext
            val workingWebView = WebView(appContext)
            webView = workingWebView

            workingWebView.setBackgroundColor(android.graphics.Color.BLACK)
            workingWebView.addJavascriptInterface(bridge, "FottyStreamBridge")
            cookieManager.setAcceptCookie(true)
            cookieManager.setAcceptThirdPartyCookies(workingWebView, true)

            workingWebView.webChromeClient = object : WebChromeClient() {
                override fun onCreateWindow(
                    view: WebView?,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: android.os.Message?
                ): Boolean {
                    // CRITICAL: Block all popup windows (Ad-jacking prevention)
                    return false
                }
            }

            workingWebView.webViewClient = object : WebViewClient() {
                private val blacklist = listOf(
                    "popads", "popcash", "onclickads", "adsterra", "bet365", "1xbet",
                    "doubleclick", "googlesyndication", "adnxs", "ads.", "tracker.",
                    "bolsterate.net", "ljline.com", "ad-score.com", "cloudfront.net/ad",
                    "steepto.com", "unblocked", "jads.co", "juicyads", "exoclick"
                )

                private fun isAd(url: String): Boolean {
                    val low = url.lowercase(Locale.US)
                    return blacklist.any { low.contains(it) } || adHostHints.any { low.contains(it) }
                }

                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?
                ): Boolean {
                    val target = request?.url?.toString().orEmpty()
                    
                    // 1. Block known ad domains
                    if (isAd(target)) {
                        Log.d(logTag, "Blocking redirect to Ad/Popup: $target")
                        return true
                    }
                    
                    // 2. Prevent the WebView from leaving the original embed domain (Redirect Hijack prevention)
                    val originalHost = Uri.parse(embedUrl).host
                    val targetHost = request?.url?.host
                    if (targetHost != null && originalHost != null && targetHost != originalHost && !isTrustedHost(targetHost)) {
                        Log.d(logTag, "Blocking cross-domain redirect: $target")
                        return true
                    }

                    captureCandidate(target)
                    return false
                }

                override fun shouldInterceptRequest(
                    view: WebView?,
                    request: WebResourceRequest?
                ): WebResourceResponse? {
                    val target = request?.url?.toString().orEmpty()
                    
                    // Always try to capture candidates from every request
                    mainHandler.post { captureCandidate(target) }

                    // Block ads immediately with empty 200 response
                    if (isAd(target)) {
                        return WebResourceResponse(
                            "text/plain",
                            "utf-8",
                            ByteArrayInputStream(ByteArray(0))
                        )
                    }

                    return super.shouldInterceptRequest(view, request)
                }

                override fun onLoadResource(view: WebView?, url: String?) {
                    captureCandidate(url)
                    super.onLoadResource(view, url)
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    captureCandidate(url)
                    if (completed) return

                    view?.evaluateJavascript(ENVIRONMENT_MOCK_SCRIPT, null)
                    view?.evaluateJavascript(SANDBOX_CLEANER_SCRIPT, null)
                    view?.evaluateJavascript(UNWRAP_IFRAME_SHELL_SCRIPT, null)
                    view?.evaluateJavascript(INTERCEPT_SCRIPT, null)
                    view?.evaluateJavascript(AUTOPLAY_KICK_SCRIPT, null)
                }

                override fun onReceivedSslError(
                    view: WebView?,
                    handler: SslErrorHandler?,
                    error: SslError?
                ) {
                    val host = runCatching {
                        Uri.parse(error?.url.orEmpty()).host?.lowercase(Locale.US).orEmpty()
                    }.getOrDefault("")
                    if (isTrustedHost(host)) {
                        handler?.proceed()
                    } else {
                        handler?.cancel()
                    }
                }
            }

            workingWebView.settings.apply {
                javaScriptEnabled = true
                javaScriptCanOpenWindowsAutomatically = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                allowFileAccessFromFileURLs = false
                allowUniversalAccessFromFileURLs = false
                mediaPlaybackRequiresUserGesture = false
                loadsImagesAutomatically = true
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                setSupportMultipleWindows(true)
                safeBrowsingEnabled = true
                userAgentString = USER_AGENT
            }

            try {
                workingWebView.loadUrl(embedUrl, mapOf("Referer" to referer, "User-Agent" to USER_AGENT))
            } catch (e: Exception) {
                Log.w(logTag, "Failed to load embed URL", e)
                completeNow(emptyList())
                return@suspendCancellableCoroutine
            }

            mainHandler.postDelayed(timeoutRunnable, timeoutSeconds.coerceAtLeast(1) * 1_000L)

            continuation.invokeOnCancellation {
                mainHandler.post {
                    if (completed) return@post
                    completed = true
                    cleanup()
                }
            }
        }
    }

    private val ENVIRONMENT_MOCK_SCRIPT = """
        (function() {
            try {
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
                Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                
                // Mock touch events for mobile spoofing
                if (!('ontouchstart' in window)) {
                    window.ontouchstart = null;
                }
            } catch (e) {}
        })();
    """.trimIndent()

    private val SANDBOX_CLEANER_SCRIPT = """
        (function() {
            try {
                const clean = () => {
                    document.querySelectorAll('iframe').forEach(f => {
                        if (f.hasAttribute('sandbox')) {
                            f.removeAttribute('sandbox');
                        }
                    });
                };
                clean();
                new MutationObserver(clean).observe(document.documentElement, { childList: true, subtree: true });
            } catch (e) {}
        })();
    """.trimIndent()

    private val INTERCEPT_SCRIPT = """
        (function() {
            function report(url) {
                if (!url || typeof url !== 'string') return;
                try {
                    var abs = new URL(url, window.location.href).href;
                    if (abs.startsWith('blob:')) return;
                    if (window.FottyStreamBridge && typeof window.FottyStreamBridge.report === 'function') {
                        window.FottyStreamBridge.report(abs);
                    }
                } catch (e) {}
            }

            function scanObj(value, depth) {
                if (!value || depth > 8) return;
                if (typeof value === 'string') {
                    report(value);
                    return;
                }
                if (typeof value === 'object') {
                    for (var key in value) {
                        try { scanObj(value[key], depth + 1); } catch (e) {}
                    }
                }
            }

            var originalFetch = window.fetch;
            if (originalFetch) {
                window.fetch = function(url, opts) {
                    var urlValue = typeof url === 'string' ? url : ((url && url.url) ? url.url : '');
                    report(urlValue);
                    return originalFetch.apply(this, arguments).then(function(response) {
                        try {
                            response.clone().text().then(function(text) {
                                try {
                                    scanObj(JSON.parse(text), 0);
                                } catch (e) {
                                    if (text.indexOf('#EXTM3U') !== -1) {
                                        report(urlValue);
                                    }
                                }
                            });
                        } catch (e) {}
                        return response;
                    });
                };
            }

            var xhrOpen = XMLHttpRequest.prototype.open;
            var xhrSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
                this.__fottyUrl = url ? url.toString() : '';
                report(this.__fottyUrl);
                return xhrOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                this.addEventListener('load', function() {
                    try {
                        scanObj(JSON.parse(this.responseText), 0);
                    } catch (e) {}
                });
                return xhrSend.apply(this, arguments);
            };

            var mediaSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
            if (mediaSrc && mediaSrc.set) {
                Object.defineProperty(HTMLMediaElement.prototype, 'src', {
                    set: function(value) {
                        report(value);
                        return mediaSrc.set.call(this, value);
                    },
                    get: mediaSrc.get
                });
            }

            function dispatchTap(node) {
                if (!node) return;
                try {
                    ['pointerdown', 'mousedown', 'touchstart', 'pointerup', 'mouseup', 'touchend', 'click'].forEach(function(name) {
                        try {
                            node.dispatchEvent(new Event(name, { bubbles: true, cancelable: true }));
                        } catch (e) {}
                    });
                    if (typeof node.click === 'function') node.click();
                } catch (e) {}
            }

            setInterval(function() {
                var selectors = [
                    '#pl_but', '#pl_but_background',
                    '.vjs-big-play-button', '.plyr__control--overlaid',
                    '.jw-display-icon-display', '.jw-icon-display',
                    '.play-button', '#play-button', '.button-play',
                    '.play-wrapper', '[aria-label="Play"]', 'button[title="Play"]'
                ];

                selectors.forEach(function(sel) {
                    try {
                        document.querySelectorAll(sel).forEach(function(node) {
                            dispatchTap(node);
                        });
                    } catch (e) {}
                });

                try {
                    var center = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
                    dispatchTap(center);
                } catch (e) {}
            }, 700);
        })();
    """.trimIndent()

    private val AUTOPLAY_KICK_SCRIPT = """
        (function() {
            var tries = 0;
            var interval = setInterval(function() {
                tries += 1;
                var selectors = [
                    '#pl_but', '#pl_but_background',
                    '.vjs-big-play-button', '.plyr__control--overlaid',
                    '.jw-display-icon-display', '.jw-icon-display',
                    '[aria-label="Play"]'
                ];
                selectors.forEach(function(sel) {
                    try {
                        document.querySelectorAll(sel).forEach(function(node) {
                            if (node && (node.offsetWidth > 0 || node.offsetHeight > 0)) {
                                if (typeof node.click === 'function') node.click();
                            }
                        });
                    } catch (e) {}
                });
                if (tries > 15) {
                    clearInterval(interval);
                }
            }, 500);
        })();
    """.trimIndent()

    private val UNWRAP_IFRAME_SHELL_SCRIPT = """
        (function() {
            try {
                var host = (window.location && window.location.host ? window.location.host.toLowerCase() : '');
                var path = (window.location && window.location.pathname ? window.location.pathname.toLowerCase() : '');
                if (host.indexOf('embedsports.top') === -1 || path.indexOf('/embed/') === -1) return;
                var frame = document.querySelector('iframe[src]');
                if (!frame) return;
                var raw = frame.getAttribute('src') || '';
                if (!raw || raw.indexOf('/ad.html') !== -1) return;
                var abs = new URL(raw, window.location.href).href;
                if (window.FottyStreamBridge && typeof window.FottyStreamBridge.report === 'function') {
                    window.FottyStreamBridge.report(abs);
                }
                window.location.replace(abs);
            } catch (e) {}
        })();
    """.trimIndent()
}
