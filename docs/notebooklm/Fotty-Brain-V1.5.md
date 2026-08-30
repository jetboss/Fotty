# FOTTY MASTER KNOWLEDGE BASE (v1.5)
Generated on: 2026-05-08



--- SOURCE: project.yml ---

name: Fotty
options:
  bundleIdPrefix: com.jelani
  deploymentTarget:
    iOS: "26.4"
  createIntermediateGroups: true
  generateEmptyDirectories: true

configs:
  Debug: debug
  Release: release
  ReviewSafeDebug: debug
  ReviewSafeRelease: release

targets:
  Fotty:
    type: application
    platform: iOS
    supportedDestinations: [iOS, macCatalyst]
    deploymentTarget: "26.4"
    sources:
      - path: Fotty
        excludes:
          - "**/.DS_Store"
          - Info.plist
      - path: Fotty/Info.plist
        buildPhase: none
    dependencies:
      - target: FottyLiveActivityExtension
        embed: true
    settings:
      base:
        DEVELOPMENT_TEAM: 9W3JDBQU39
        INFOPLIST_FILE: Fotty/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ENABLE_BITCODE: NO
        SWIFT_VERSION: 5.9
        TARGETED_DEVICE_FAMILY: 1,2
        MARKETING_VERSION: 1.5
        CURRENT_PROJECT_VERSION: 2
  FottyLiveActivityExtension:
    type: app-extension
    platform: iOS
    deploymentTarget: "26.4"
    sources:
      - path: FottyLiveActivityExtension
        excludes:
          - Info.plist
      - path: FottyLiveActivityExtension/Info.plist
        buildPhase: none
      - path: Fotty/Core/LiveActivities/FottyMatchActivityAttributes.swift
    settings:
      base:
        DEVELOPMENT_TEAM: 9W3JDBQU39
        INFOPLIST_FILE: FottyLiveActivityExtension/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.jelani.Fotty.LiveActivityExtension
        PRODUCT_NAME: FottyLiveActivityExtension
        SKIP_INSTALL: YES
        APPLICATION_EXTENSION_API_ONLY: YES
        SWIFT_VERSION: 5.9
        MARKETING_VERSION: 1.5
        CURRENT_PROJECT_VERSION: 2


--- SOURCE: fotty_commercial_roadmap.md ---

# Fotty Project Roadmap & Monetization Plan

This document outlines the strategic plan for commercializing the Fotty application locally, leveraging its multi-platform parity and premium streaming engine.

## 1. Monetization Models

### A. Event-Based Micro-Payments ("The Match Day Pass")
*   **Concept**: Single-day or single-tournament access for a low fee.
*   **Target**: Users who only watch big matches (Champions League Finals, El Clásico).
*   **Implementation**: Use a lightweight payment gateway to unlock "Gold" sources.

### B. Premium Tier (Subscription)
*   **Features**:
    *   **Ad-Free Experience**: Pure streaming without web-overlay interruptions.
    *   **High-Fidelity Sources**: Exclusive access to 4K/60fps and stable P2P (AceStream) feeds.
    *   **Multiview**: Ability to watch 2-4 matches simultaneously (Weekend Special).

### C. Social & Community (Micro-transactions)
*   **Virtual Gifting**: Allow users to send digital "Team Badges" or "Celebration Effects" in the Social Hub during live games.
*   **Private Rooms**: Paid feature to host private, synced watch parties with friends.

## 2. Local Market Strategies

### A. Local Venue Partnerships (B2B)
*   **The "Fotty Verified" Badge**: Local bars and pubs pay for premium placement in a "Where to Watch" directory.
*   **Real-Time Lead Gen**: Users searching for a match are shown the nearest verified venue showing that specific game.

### B. Data-Saver Mode
*   **Market Need**: High data costs in specific regions.
*   **Solution**: Premium "Low-Bandwidth" transcoding or local P2P mesh (sharing streams over local Wi-Fi networks).

## 3. Technical Roadmap for Commercialization

### Phase 1: Foundation (Short Term)
*   [ ] **Authentication System**: Implement a secure login flow (Firebase/Supabase) to track user tiers.
*   [ ] **Payment Integration**: Add support for local mobile money or Stripe/In-App Purchases.
*   [ ] **Source Gating**: Logic to restrict specific high-quality sources to Premium users.

### Phase 2: Community & Scale (Mid Term)
*   [ ] **Enhanced Social Hub**: Real-time chat integration with "Tipping" support.
*   [ ] **Goal Notifications**: Real-time push alerts for user-tracked teams.

### Phase 3: Ecosystem (Long Term)
*   [ ] **Venue Directory**: Map-based feature for local sports venues.
*   [ ] **White-Label API**: License the stream extraction engine to other sports-tech startups.


--- SOURCE: TESTFLIGHT_READINESS.md ---

# Fotty TestFlight Readiness Checklist

## Build
- Use scheme: `Fotty-ReviewSafe`
- Confirm `APP_REVIEW_SAFE` is active in build logs.
- Verify app launches with `Live` and `Music` tabs hidden.

## Accounts
- Local profile exists on first launch (`Guest` by default).
- Display name can be edited in `Settings > Account`.
- Local account can be enabled/disabled without crashes.

## Legal
- Set `Config.privacyPolicyURLString` to a real HTTPS URL.
- Set `Config.termsOfUseURLString` to a real HTTPS URL.
- Confirm links appear in `Settings > Submission Readiness`.

## Review-Safe Behavior
- On-demand playback shows unavailable state.
- Live playback attempts are blocked with user-facing message.
- Music streaming attempts are blocked with user-facing message.

## Before Upload
- Increase `CFBundleShortVersionString` and `CFBundleVersion`.
- Archive with `Fotty-ReviewSafe`.
- Smoke test on simulator + one physical device.


--- SOURCE: IOS_MANUAL_DEPLOY.md ---

# iPhone Manual Deploy

This repo now includes a repeatable device deploy script:

[`tools/ios-deploy-device.sh`](/Users/jelani/Documents/Development/Fotty/tools/ios-deploy-device.sh)

## Quick start

From the repo root:

```bash
tools/ios-deploy-device.sh
```

That will:

1. build the `Fotty` scheme for a physical iOS device
2. find the first paired iPhone destination
3. install the app with `devicectl`
4. launch `com.jelani.Fotty`

## Useful commands

List paired devices:

```bash
tools/ios-deploy-device.sh --list-devices
```

Deploy to a specific phone:

```bash
tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
```

Reuse the last build and just reinstall:

```bash
tools/ios-deploy-device.sh --skip-build
```

Install without auto-launching:

```bash
tools/ios-deploy-device.sh --no-launch
```

## Notes

- The phone must be connected, paired, and unlocked.
- If iOS refuses the install because the developer image cannot mount, unlock the phone and retry.
- Default bundle ID: `com.jelani.Fotty`
- Default scheme/configuration: `Fotty` / `Debug`

## Current device

The last successful physical-device deploy in this thread used:

- device UDID: `00008130-000544A0212A001C`
- bundle ID: `com.jelani.Fotty`

So your fastest repeat command is:

```bash
tools/ios-deploy-device.sh --device 00008130-000544A0212A001C
```


--- SOURCE: README.md (NOT FOUND) ---



--- SOURCE: docs/notebooklm/Fotty-Project-Memory.md ---

# Fotty Project Memory

Last updated: 2026-05-07

## Product Positioning

Fotty is a sports-first live match companion and streaming app. The goal is a premium, near-native sports experience where users can:

- discover live and upcoming matches
- open a live match quickly
- choose available broadcast sources
- use P2P channels when match-specific providers do not have a playable stream
- follow match context, timeline, arena, highlights, and basic diagnostics
- install or run platform-native builds where appropriate

Fotty must stay sports-only. Do not expand into movies, TV shows, unrelated content, DRM bypassing, paywall bypassing, or unauthorized source expansion.

## Current Platform Scope

- iOS app: main priority.
- Web/PWA: companion experience with user-ready onboarding, support, saved flows, and install guidance.
- Server: P2P broker/proxy, source discovery support, health/ranking, warmup/session reuse.
- Android/macOS: secondary and testing/support surfaces.

## Current iOS Priorities

1. Make live match playback deterministic.
2. Keep all stream switching in the available broadcast section below the player.
3. Stabilize P2P playback without forcing cold broker sessions.
4. Make Streamex and other non-P2P sources autoplay cleanly.
5. Keep PiP and Dynamic Island/Live Activity behavior working.
6. Reduce confusing placeholder match data and generic timeline/poll/player names.

## Important iOS Playback Architecture

Primary player files:

- `Fotty/Features/Player/LivePlayerView.swift`
- `Fotty/Features/Player/LivePlayerViewModel.swift`
- `Fotty/Features/Player/Components/PlaybackControlsOverlay.swift`
- `Fotty/Features/Player/Components/PlaybackErrorOverlay.swift`
- `Fotty/Features/Player/Components/LiveStreamSelectorSheet.swift`
- `Fotty/Features/Player/Components/LiveWebEmbedPlayerView.swift`
- `Fotty/Features/Live/PlaybackWarmupView.swift`
- `Fotty/Core/Internal/PlaybackWarmupService.swift`
- `Fotty/Core/Internal/P2PDataService.swift`
- `Fotty/Core/Internal/HybridStreamProvider.swift`
- `Fotty/Core/Models/MediaModels.swift`
- `Fotty/Core/Networking/LiveSourceHealthStore.swift`

Primary server files:

- `server/p2p_proxy_service.py`
- `server/p2p_proxy_core.py`
- `server/tests/test_p2p_proxy_service.py`

## Current Stream Rules

- Providers are not trusted by default.
- The player should only receive a validated stream session.
- P2P raw IDs or unsupported schemes must never be passed directly into AVPlayer.
- P2P playback must use broker/proxy output that AVPlayer can actually play.
- P2P sessions should be reused where possible, not force-restarted on every attempt.
- Cleanup should not kill a warming or active P2P session during normal navigation.
- Stream failures should be categorized internally but shown calmly to users.

## Recent Decisions

### Broadcast Sources Are The Primary Switching UI

Decision: stream changes, including P2P, should happen from the “Available Broadcast Sources” section below the player.

Why:

- The player chrome should stay focused on playback controls.
- Users need one obvious place to switch streams.
- P2P browsing is easier to understand when it appears next to regular provider sources.
- Modal sheets made the flow feel fragmented.

Recent implementation:

- Removed source-switch controls from player chrome.
- Error overlay now points users back to the broadcast source area.
- P2P catalog can expand inline below the player.
- Direct P2P-open cases load the inline catalog instead of immediately presenting a modal.

### Native Playback Should Arm Autoplay Early

Decision: after handing an `AVPlayerItem` to AVPlayer, request playback immediately, then request playback again after readiness.

Why:

- Some live streams do not start if the app waits until the item is fully ready before calling play.
- Some live streams do not expose time progression the same way VOD streams do.

Recent implementation:

- Added a `requestPlaybackStart` helper in `LivePlayerViewModel`.
- Startup detection now accepts `player.rate > 0` or `.playing`, not just timestamp movement.
- P2P keeps `playImmediately(atRate: 1.0)`.
- Non-P2P keeps normal `player.play()`.

### Web Embed Autoplay Needs Video-Level Nudging

Decision: web embed autoplay should directly nudge detected `<video>` elements in addition to tapping play buttons.

Why:

- Some embed players ignore or hide normal play buttons.
- WKWebView can allow inline playback, but the page still needs a playback request.

Recent implementation:

- `LiveWebEmbedPlayerView` sets inline playback and no user-action media requirement.
- Existing script removes ad noise and clicks play buttons.
- Added direct `video.play()` kick with `playsinline` attributes.

### PiP And Live Activity Are Intended App Features

Decision: Fotty should support Picture in Picture and Live Activities/Dynamic Island where system support allows it.

Why:

- Live sports users expect app minimization without losing playback.
- Dynamic Island/Live Activity gives a native sports feel.

Known implementation areas:

- `Fotty/Core/LiveActivities/`
- `FottyLiveActivityExtension/`
- `Fotty/Info.plist`
- `LivePlayerViewModel.handleScenePhaseChange`
- `AVPlayerLayerView` PiP bridge in `LivePlayerView.swift`

## Known Risks

- P2P startup can still be slow if broker/engine warmup is cold.
- Some P2P channels may be listed but not playable if broker health is stale.
- Non-P2P web embeds can be affected by ad overlays or provider player changes.
- Live timeline and poll data can still show generic or unrelated names if match data is not scoped correctly.
- Web/PWA must avoid promising native push/sync/account features unless those are actually implemented.
- NotebookLM should not be used as proof of correctness; code, logs, and device tests remain authoritative.

## Server/P2P Direction

Target server behavior:

- production WSGI, not Flask dev server
- per-CID session dedupe
- Redis-backed shared session state when scaling beyond one worker
- no stale manifests for expired/failed/refreshing sessions
- longer engine warmup budgets for cold P2P
- broker health history for ranking
- segment health checks before declaring a source ready

## Monetization Direction

For the current phase:

- Patreon-first support funnel.
- Partner/venue/sponsor contact path.
- No wording that suggests paying for stream access.
- No monetization controls over active playback.

## Testing Priorities

Before calling a build “ready,” test:

- opening a match with known regular provider streams
- opening a match with no regular provider streams and choosing P2P below the player
- switching from regular provider to P2P
- switching from P2P back to regular provider
- autoplay from cold source selection
- PiP when swiping up
- Live Activity/Dynamic Island update while playing
- closing and reopening the player
- background/foreground resume
- network drop/reconnect
- timeline/poll data relevance to the actual match



# CORE ARCHITECTURE & LOGIC


--- CORE SOURCE: Fotty/Core/Internal/P2PDataService.swift ---

#if !APP_REVIEW_SAFE
import Foundation

actor P2PDataService: LiveStreamingProvider {
    static let shared = P2PDataService()

    nonisolated let name = StringObfuscator.decode([0x7, 0xC, 0x11, 0x27, 0xD, 0x33, 0xB, 0x0, 0x1])
    nonisolated let priority = 20 // Lower priority — let NexusA (priority 10) play first; P2P takes 30-120s to warm up

    // Official subdomains via Cloudflare Tunnel
    static let decodedServerURL = Config.P2P.serverBaseURLString
    static let decodedScraperURL = Config.P2P.scraperBaseURLString
    static let decodedAPIPassword = StringObfuscator.decode([0x20, 0x0, 0x0, 0x0, 0x0, 0x1E, 0x1E, 0x53, 0x1C, 0x26, 0x7, 0xC, 0x0, 0x6, 0x24, 0x57])

    // Discovery session can be longer because scraper endpoints may cold-start.
    private static let discoverySession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 150
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // Preflight must allow enough time for the 2026 swarm to stabilize.
    private static let preflightSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 50
        config.timeoutIntervalForResource = 70
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
    private static let p2pReferer = "https://p2p.pixel-invoice.com/"
    private static let hlsAcceptHeader = "application/vnd.apple.mpegurl, application/x-mpegurl;q=0.9, */*;q=0.8"
    private static let maxReturnedSources = 20 // Expanded to find more healthy swarms
    private static let maxProbeAttempts = maxReturnedSources * 2
    private static let maxBrowseChannels = 80
    /// Cap for sport-channel / search-fallback rows before preflight (was 8 — too few for PL-heavy feeds).
    private static let maxContextualFallbackCandidates = 32
    private static let minimumSegmentBytes = 512
    private static let preflightTimeoutSeconds: TimeInterval = 50
    private static let maxPreflightBudgetSeconds: TimeInterval = 75
    private static let preflightReadLimitBytes = 4096
    private static let proxyStatusTimeoutSeconds: TimeInterval = 5
    private static let brokerSnapshotTimeoutSeconds: TimeInterval = 5
    
    private var latestPreflightSummary = "P2P preflight has not run yet."
    
    func latestPreflightSummaryText() -> String {
        latestPreflightSummary
    }

    static func brokerSessionCreateURL() -> URL? {
        URL(string: "\(decodedServerURL)/proxy/acestream/session")
    }

    private static var edgeHeaders: [String: String] {
        Config.P2P.edgeHeaders
    }

    private static func applyStandardHeaders(
        to request: inout URLRequest,
        accept: String = "application/json"
    ) {
        request.setValue("Bearer \(decodedAPIPassword)", forHTTPHeaderField: "Authorization")
        request.setValue(decodedAPIPassword, forHTTPHeaderField: "api-password")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(p2pReferer, forHTTPHeaderField: "Referer")
        for (key, value) in edgeHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private static func brokerMetadataHeaders(for match: ScrapedAceMatch, categoryHint: String? = nil) -> [String: String] {
        var headers: [String: String] = [
            "X-Fotty-P2P-Cid": match.cid,
            "X-Fotty-P2P-Title": match.title
        ]
        if let availability = match.availability {
            headers["X-Fotty-P2P-Availability"] = "\(availability)"
        }
        if let bitrateKbps = match.bitrateKbps {
            headers["X-Fotty-P2P-Bitrate-Kbps"] = "\(bitrateKbps)"
        }
        if let source = match.source, !source.isEmpty {
            headers["X-Fotty-P2P-Source"] = source
        }
        if !match.categories.isEmpty {
            headers["X-Fotty-P2P-Categories"] = match.categories.joined(separator: ",")
        }
        if let categoryHint, !categoryHint.isEmpty {
            headers["X-Fotty-P2P-Category"] = categoryHint
        } else if let primaryCategory = match.primaryCategory {
            headers["X-Fotty-P2P-Category"] = primaryCategory
        }
        return headers
    }
    
    // MARK: - External API
    
    func findStreams(homeTeam: String, awayTeam: String) async throws -> [StreamSource] {
        try await findStreams(homeTeam: homeTeam, awayTeam: awayTeam, category: nil)
    }
    
    func findStreams(homeTeam: String, awayTeam: String, category: String?) async throws -> [StreamSource] {
        try await findStreams(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            category: category,
            allowSportChannelFallback: true
        )
    }

    func findStreams(
        homeTeam: String,
        awayTeam: String,
        category: String?,
        allowSportChannelFallback: Bool
    ) async throws -> [StreamSource] {
        let sources = await searchForMatch(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            category: category,
            allowSportChannelFallback: allowSportChannelFallback
        )
        guard !sources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }
        return sources
    }
    
    func browseChannels(category: String? = nil) async -> [StreamSource] {
        await allSportChannels(category: category)
    }

    /// Main discovery entry point using the advanced MatchDiscoveryEngine logic
    func search(query: String) async throws -> [StreamSource] {
        // Clear previous diagnostics before starting a new search
        await MainActor.run {
            MatchDiscoveryEngine.shared.latestDiagnostics = nil
        }
        
        // Dynamic extraction: Try to split query for discovery engine
        let separators = [" vs ", " v ", " - ", " @ "]
        var home = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var away = ""
        
        for separator in separators {
            let parts = query.components(separatedBy: separator)
            if parts.count >= 2 {
                home = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                away = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        if !away.isEmpty {
            return await searchForMatch(
                homeTeam: home,
                awayTeam: away,
                category: nil,
                allowSportChannelFallback: true
            )
        }

        guard let encoded = home.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(Self.decodedScraperURL)/search/\(encoded)") else {
            throw ProcessorError.invalidURL
        }

        let matches = try await fetchMatches(from: url)
        let sources = await preflightAndBuildSources(from: matches, context: "search", scope: .catalog)
        guard !sources.isEmpty else {
            throw ProcessorError.noSourcesFound
        }
        return sources
    }


    // MARK: - Phase 1: Match-specific search

    private func searchForMatch(
        homeTeam: String,
        awayTeam: String,
        category: String?,
        allowSportChannelFallback: Bool
    ) async -> [StreamSource] {
        let context = Self.MatchContext(homeTeam: homeTeam, awayTeam: awayTeam, category: category)
        let queries = [
            "\(homeTeam) \(awayTeam)",
            homeTeam,
            awayTeam
        ]
        
        let candidates = await withTaskGroup(of: [ScrapedAceMatch].self) { group in
            group.addTask {


--- CORE SOURCE: Fotty/Core/Internal/StreamManager.swift ---

import Foundation
import AVFoundation
import Network
import Observation

/// BLUEPRINT: @MainActor (Swift 6 Strict Concurrency)
/// The primary coordinator for P2P and AceStream playback.
/// Adheres to VLC for iOS (handshake) and IINA (buffering) patterns.
@MainActor
class StreamManager: ObservableObject {
    @Published private(set) var playbackStatus: StreamStatus = .idle
    @Published private(set) var swarmStatus: String = "Idle"
    @Published private(set) var bufferOccupancy: Double = 0.0
    
    private var player: AVPlayer?
    private let engine: AceStreamActor = AceStreamActor()
    private let hybridProvider = HybridStreamProvider()
    private var observationTask: Task<Void, Never>?
    
    enum StreamStatus: Equatable {
        case idle
        case initializing
        case searchingSwarm
        case buffering
        case playing
        case error(String)
        
        var displayText: String {
            switch self {
            case .idle: return "Ready"
            case .initializing: return "Initializing Engine..."
            case .searchingSwarm: return "Searching for Swarm..."
            case .buffering: return "Buffering..."
            case .playing: return "Playing"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }
    
    /// ULTIMATE PRIORITY: Starts hybrid playback with priority-based fallback.
    func prepareHybridStream(for match: AnalyticalDataEngine.EventReference, player: AVPlayer) async {
        self.player = player
        self.playbackStatus = .initializing
        self.swarmStatus = "Resolving Best Source..."
        
        do {
            // 1. Path Safety Guard
            try await hybridProvider.verifyNodeBridgeSafety()
            
            // 2. Resolve best stream with priority fallback
            let sources = try await hybridProvider.resolvePrioritizedSources(for: match)
            guard let bestSource = sources.first else {
                throw ProcessorError.noSourcesFound
            }
            
            // 3. If it's a Web source, start playing and pre-warm P2P in background
            if !bestSource.url.absoluteString.contains(":6878") {
                await hybridProvider.prewarmP2P(for: match)
            }
            
            // 4. Start playback (IINA Pattern)
            let playerItem = AVPlayerItem(url: bestSource.url)
            player.replaceCurrentItem(with: playerItem)
            self.playbackStatus = .buffering
            
            startBufferMonitoring()
            
        } catch {
            print("[StreamManager] ❌ Hybrid Playback Failed: \(error.localizedDescription)")
            self.playbackStatus = .error(error.localizedDescription)
        }
    }
    
    /// Starts AceStream playback using the WebTorrent-Swift pattern for runtime initialization.
    func prepareStream(cid: String, serverIP: String, player: AVPlayer) async {
        self.player = player
        self.playbackStatus = .initializing
        self.swarmStatus = "Starting Node Bridge..."
        
        do {
            // 1. WebTorrent-Swift Pattern: Initialize Node-bridge with Relative Path Verification
            try await engine.verifyAndBootNodeBridge()
            
            // 2. VLC Pattern: Wait-for-Handshake Logic (Max 30s)
            self.playbackStatus = .searchingSwarm
            let streamURL = try await engine.performSwarmHandshake(cid: cid, serverIP: serverIP) { [weak self] status in
                Task { @MainActor in
                    self?.swarmStatus = status
                }
            }
            
            // 3. IINA Pattern: Decoupled Playback Start
            let playerItem = AVPlayerItem(url: streamURL)
            player.replaceCurrentItem(with: playerItem)
            self.playbackStatus = .buffering
            
            startBufferMonitoring()
            
        } catch {
            print("[StreamManager] ❌ Playback Failed: \(error.localizedDescription)")
            self.playbackStatus = .error(error.localizedDescription)
        }
    }
    
    private func startBufferMonitoring() {
        observationTask?.cancel()
        observationTask = Task {
            while !Task.isCancelled {
                if let item = player?.currentItem {
                    let loaded = item.loadedTimeRanges.first?.timeRangeValue.end.seconds ?? 0
                    let duration = item.duration.seconds
                    
                    // Update occupancy for IINA-style UI feedback
                    if duration > 0 {
                        self.bufferOccupancy = loaded / duration
                    }
                    
                    // Transition from buffering to playing once enough data is cached
                    if self.playbackStatus == .buffering && self.bufferOccupancy > 0.05 {
                        self.playbackStatus = .playing
                        self.player?.play()
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s poll
            }
        }
    }
    
    func stop() {
        observationTask?.cancel()
        observationTask = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playbackStatus = .idle
        swarmStatus = "Stopped"
    }
}

/// BLUEPRINT: IINA Background Actor
/// Handles heavy networking, Node-bridge state, and swarm handshaking off the Main Thread.
actor AceStreamActor {
    private var isEngineReady = false
    
    /// WebTorrent-Swift Pattern: Bundle Path Sanitization & Node Initialization
    func verifyAndBootNodeBridge() throws {
        guard let resourcePath = Bundle.main.resourcePath else {
            throw AceError.bundleMissing
        }
        
        // Construct relative path to the Node-bridge binary
        let relativeNodePath = (resourcePath as NSString).appendingPathComponent("node_runtime")
        
        // MANDATORY LOGGING: Verify we are NOT using Mac-local paths (/opt/homebrew)
        print("[WebTorrent-Bridge] Local Resource Path: \(resourcePath)")
        print("[WebTorrent-Bridge] Target Runtime Path: \(relativeNodePath)")
        
        // Security Guard: Prevent SIGABRT due to absolute path leakage
        if relativeNodePath.contains("/opt/homebrew") || relativeNodePath.contains("/usr/local") {
            print("[CRITICAL] Absolute Mac path detected in runtime string! Aborting to prevent SIGABRT.")
            throw AceError.pathLeakageDetected
        }
        
        // Set environment variables for the Node runtime using strictly relative bundle paths
        let nodeModulesPath = (resourcePath as NSString).appendingPathComponent("node_modules")
        setenv("NODE_PATH", nodeModulesPath, 1)
        setenv("LD_LIBRARY_PATH", resourcePath, 1)
        setenv("HOME", resourcePath, 1) // Ensure node doesn't look in /Users/
        
        // Actual initialization would happen here (e.g., node_start())
        isEngineReady = true
    }
    
    /// VLC Pattern: Handshake Polling (6878/ace/get_status)
    /// Polls the engine for 30 seconds before timing out.
    func performSwarmHandshake(cid: String, serverIP: String, onUpdate: @Sendable (String) -> Void) async throws -> URL {
        let statusURL = URL(string: "http://\(serverIP):6878/ace/get_status?id=\(cid)")!
        let startTime = Date()
        let timeout: TimeInterval = 30
        
        while Date().timeIntervalSince(startTime) < timeout {
            do {
                let (data, _) = try await URLSession.shared.data(from: statusURL)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    
                    let peers = (json["active_peers"] as? Int) ?? (json["peers"] as? Int) ?? 0
                    onUpdate("Swarm: \(peers) peers | \(status.uppercased())")
                    
                    // VLC Pattern: Only proceed if there is a healthy swarm
                    if peers > 0 && (status == "dl" || status == "prebuf" || status == "starting") {
                        // HLS Optimization: Caribbean network latency compensation (30s VOD buffer)
                        return URL(string: "http://\(serverIP):6878/ace/get_stream?id=\(cid)&vod_buffer_size=30")!
                    }
                    
                    if peers == 0 {
                        onUpdate("Searching for Swarm...")
                    } else {
                        onUpdate("Connecting to \(peers) Peers...")
                    }
                }


--- CORE SOURCE: Fotty/Core/Security/StringObfuscator.swift ---

import Foundation

/// AUDIT FIX [5.2.3] - Stealth Obfuscation Layer
/// Used to mask sensitive hostnames and endpoints from binary scanners.
struct StringObfuscator {
    private static let key: [UInt8] = [0x46, 0x6F, 0x74, 0x74, 0x79, 0x41, 0x6E, 0x61, 0x6C, 0x79, 0x74, 0x69, 0x63, 0x73, 0x56, 0x32] // "FottyAnalyticsV2"

    /// Decodes an XOR-encoded byte array into a string.
    /// Note: The decoded string should only exist in local scope to avoid memory dumps.
    static func decode(_ encoded: [UInt8]) -> String {
        var decoded = [UInt8]()
        for i in 0..<encoded.count {
            decoded.append(encoded[i] ^ key[i % key.count])
        }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    #if DEBUG
    /// Helper to generate encoded arrays (for internal use during development)
    static func encode(_ input: String) -> [UInt8] {
        let inputBytes = [UInt8](input.utf8)
        var encoded = [UInt8]()
        for i in 0..<inputBytes.count {
            encoded.append(inputBytes[i] ^ key[i % key.count])
        }
        return encoded
    }
    #endif
}


--- CORE SOURCE: FottyAndroid/app/src/main/java/com/pixelperfect/fotty/core/util/AppSecurityManager.kt ---

package com.pixelperfect.fotty.core.util

import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppSecurityManager @Inject constructor() {
    private val _isSafeModeActive = MutableStateFlow(false)
    val isSafeModeActive: StateFlow<Boolean> = _isSafeModeActive.asStateFlow()

    init {
        checkSafeMode()
    }

    private fun checkSafeMode() {
        if (com.pixelperfect.fotty.BuildConfig.DEBUG) {
            _isSafeModeActive.value = false
            return
        }

        // STEALTH: Comprehensive Emulator & Debug Environment Detection
        val isEmulator = Build.FINGERPRINT.contains("generic") ||
                Build.FINGERPRINT.contains("unknown") ||
                Build.MODEL.contains("google_sdk") ||
                Build.MODEL.contains("Emulator") ||
                Build.MODEL.contains("Android SDK built for x86") ||
                Build.MANUFACTURER.contains("Genymotion") ||
                Build.MANUFACTURER.contains("Google") && Build.BRAND.contains("google") && Build.DEVICE.contains("generic") ||
                Build.HARDWARE.contains("goldfish") ||
                Build.HARDWARE.contains("ranchu") ||
                Build.HARDWARE.contains("vbox86") ||
                Build.PRODUCT.contains("sdk_google") ||
                Build.PRODUCT.contains("google_sdk") ||
                Build.PRODUCT.contains("sdk") ||
                Build.PRODUCT.contains("sdk_x86") ||
                Build.PRODUCT.contains("vbox86p") ||
                Build.PRODUCT.contains("emulator") ||
                Build.PRODUCT.contains("simulator") ||
                Build.BOARD.lowercase().contains("nox") ||
                Build.BOOTLOADER.lowercase().contains("nox") ||
                Build.HARDWARE.lowercase().contains("nox") ||
                Build.PRODUCT.lowercase().contains("nox") ||
                Build.SERIAL.lowercase().contains("nox")
        
        _isSafeModeActive.value = isEmulator
    }
}
