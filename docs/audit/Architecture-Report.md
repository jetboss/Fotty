# Fotty iOS Video Playback: Architecture & Pipeline Audit

## 1. Executive Summary
The Fotty iOS playback system is a hybrid architecture utilizing native `AVPlayer` for direct stream playback and `WKWebView` for fallback embedded players. On-demand content (VOD) relies on a headless scraping layer (`WebViewRenderer`), while live sports utilize a staggered parallel resolution race. Both systems heavily depend on a `LocalStreamProxy` for header injection and manifest rewriting.

## 2. Playback Pipeline Mapping

### 2.1 Live Sports Pipeline
1. **Trigger**: `LivePlayerView` onAppear -> `viewModel.loadCurrentSource()`.
2. **Resolution**: `LiveStreamResolver` runs a race between:
    - **CoreMedia Track**: Scrapes native HLS/MP4 URLs.
    - **P2P Track**: Validates AceStream hashes via `AceSessionEngine`.
3. **Initialization**: `AVPlayer` is initialized with a `StreamSource`. If headers are required, the URL is routed through `LocalStreamProxy`.
4. **Rendering**: `AVPlayerLayerView` (UIKit wrapper) displays the video.
5. **Observability**: `LivePlayerViewModel` monitors `AVPlayerItem.status` and `NotificationCenter` for stalls.

### 2.2 VOD (Movies/TV) Pipeline
1. **Trigger**: `VideoPlayerView` task -> `loadSources()`.
2. **Resolution**: `ContentResolutionService.shared.resolve()` calls `WebViewRenderer`.
3. **Scraping**: Headless `WKWebView` loads provider embeds (VidSrc, etc.), intercepts network requests via JS injection, and "rips" the `.m3u8` source.
4. **Initialization**: `AVPlayer` loads the ripped source, almost always via `LocalStreamProxy` since providers require specific Referers/Cookies.
5. **Rendering**: `AVPlayerLayerView` displays the video.
6. **Observability**: `VideoPlayerView` uses a polling `Stall Watchdog` (30s threshold).

## 3. Core Components

| Component | Responsibility | Risk Level |
|-----------|----------------|------------|
| `LocalStreamProxy` | Intercepts HLS requests, injects headers, rewrites manifests for segment auth. | **High** (Lifecycle/Port issues) |
| `WebViewRenderer` | Headless scraping of obfuscated provider players. | **High** (JS-gate changes) |
| `AVPlayerLayerView` | Bridge between SwiftUI and UIKit `AVPlayerLayer`. | Low |
| `LiveStreamResolver` | Concurrent resolution of live sources. | Medium |

## 4. Identified Failure Modes (The "Black Screen" Causes)

### 4.1 Proxy Silent Failures
If `LocalStreamProxy` fails to start or the port is blocked, the `AVPlayer` attempts to load `http://127.0.0.1`, which fails. If the player logic doesn't catch the underlying network error, it remains on a black screen (loading state).

### 4.2 Auth-Header Gaps
Providers often require the `Referer` to match their domain. While the proxy injects these, any failure in manifest rewriting (missing a relative URL pattern) causes segments to be fetched without headers, leading to 403 Forbidden errors. `AVPlayer` often handles 403s by simply stopping, resulting in a black screen.

### 4.3 Readiness Timeout Mismatch
VOD streams through the proxy and scraper can take 15-25 seconds to stabilize. If the UI watchdog triggers at 10-15 seconds, it might kill a perfectly valid but slow-loading stream.

### 4.4 Simulator Constraints
`WebViewRenderer` is disabled in the simulator to prevent crashes. This prevents developers from testing the VOD pipeline without a physical device, leading to regression-prone code.

## 5. Next Steps (Phase 2)
1. **Instrument the Pipeline**: Add deep logging for `AVPlayerItem.errorLog` and `accessLog`.
2. **Proxy Health Check**: Add a ping mechanism to ensure the local proxy is alive before passing the URL to `AVPlayer`.
3. **Stream Validator**: Implement a "Contract Validator" to check if the URL returned by the scraper actually returns video/m3u8 data before trying to play it.
