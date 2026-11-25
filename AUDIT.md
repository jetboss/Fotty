# Fotty iOS audit — 8 November 2026

Read-only audit of the native app at `wip/ios-3.0-baseline` (3.0.0 build 244, HEAD `e7761af`, uncommitted Worker edits from a sibling session excluded). No build, simulator, install, commit or deployment was performed. Line numbers are navigation anchors for the inspected working tree, not permanent references. Where a claim rests on reading code rather than running it, the finding says so.

---

## 1. Executive summary

**Overall health: structurally sound transport and security engineering, buried under a policy layer that has grown faster than anyone can reason about.** 88k lines of app Swift (214 files) with 71k lines of tests, zero third-party dependencies, careful loopback relay and redirect hygiene, and bounded diagnostics. But the two files that decide whether the owner sees a stream — `LivePlayerViewModel.swift` (4,685 lines) and `HybridStreamProvider.swift` (2,230 lines, actually `LiveStreamResolver`) — plus roughly a dozen `@MainActor` "policy" enums, encode so many guards that a legitimate match can be silently refused Watch with no error, no log and no test that would catch it.

**Five biggest problems**

1. **Watch eligibility is gated on process-local, short-lived evidence.** After a relaunch the discovery index is empty, the catalog availability index is empty until a background loop runs, and the registry snapshot may lack the match. `CurrentEventBroadcastPolicy.actionForCurrentEvent` then returns `nil` or "Check streams" instead of Watch, so `HybridStreamProvider`'s direct-adapter fallback is never reached. This is the best explanation for "reopened Fotty, no streams appeared". (§2.1-A, Critical)
2. **A web-embed source that dies mid-match never triggers a fresh resolver pass.** The "exhausted match lookup" that re-queries CS/AS/TV after a terminal failure is guarded by `!isUsingWebEmbed` (`LivePlayerViewModel.swift:3262`). Half-time failures on a web source go straight to the terminal error screen. (§2.1-B, Critical)
3. **Live status has a hard 30-minute freshness fence.** `SportsFixture.isLive(at:)` requires `observedAt` within 30 min; `OptionalSourceLookupPolicy` returns `nil` otherwise. One missed device fixture refresh during a match removes Watch from a genuinely live fixture, with the UI reading "Broadcast unconfirmed". (§2.2-A, High)
4. **Two god objects own all playback and resolution state.** `LivePlayerViewModel` has ~60 mutable state fields, 10 stored `Task` handles and three different owner/generation fencing schemes. Correctness is asserted by 5,400-line policy tests rather than by structure. Every incident fix adds another guard. (§2.4-A, High)
5. **A 1.6 MiB JSON registry snapshot lives in `UserDefaults`**, is re-serialised on every refresh, and takes "nearly 12 s" to validate by the code's own comment. Combined with four polling loops started from `MainTabView`, launch and foreground return are heavier than they need to be. (§2.6-A, §2.8-A, Medium-High)

**Root-cause hypothesis for the 7 Nov Leeds–Tottenham incident** (two separate failures, as the handoff requested):

- *Half-time stream failure*: most probably a web-embed source (StreamEx/Score808 family are the only default-enabled providers; CS/AS/TV default OFF). Web stall → one same-source reload → `exhaustSource` → `nextPlayableSource` among the sessions already in hand → none → terminal failure, because the fresh-lookup branch is skipped for web embeds (§2.1-B). Not provable without the device's `fotty.quality.records.v1` export; the records `source_failure`, `automatic_failover`, `terminal_failure` and the absence of `direct_fallback_lookup` would confirm it.
- *No streams after reopening*: cold process → `FixtureStreamDiscoveryIndex` empty → cached registry (12:25 UTC receipt) has no CS link → `FixtureCatalogAvailabilityIndex` empty until the 60 s collector loop completes a CS catalog read (7 s timeout, 300 s per-provider cooldown) → row shows "Broadcast unconfirmed" / "Check streams" rather than Watch (§2.1-A). If the sports-fixture lane also failed on reopen, the 30-minute `isLive` fence removes even "Check streams" (§2.2-A). The cloud-side 75-minute CS cadence gap is real but is a contributing cause, not the native defect: a cloud *hint* should never be a native *gate*, and today it mostly is.

---

## 2. Findings

Severity: **Critical** = can directly produce the owner's reported failures; **High** = likely to cause user-visible breakage or data loss; **Medium** = correctness/maintainability risk; **Low** = hygiene.

### 2.1 Streaming & playback

**A. Critical — Cold-start Watch gate suppresses discovery before any adapter runs**
`Fotty/Core/Models/CurrentEventBroadcastPolicy.swift:136-190` (`actionForCurrentEvent`), `:331-470` (`FixtureSourceLookupPresentation.state`), `Fotty/App/MainTabView.swift:231-247`.
Watch is offered only if one of: (a) the primary catalog already lists a source, (b) `FixtureStreamDiscoveryIndex` has a fresh candidate (60 s lifetime, in-memory), (c) `BroadcastRegistryClient` has a link, or (d) `FixtureCatalogAvailabilityIndex` lists the provider. After relaunch (b) and (d) are empty; (c) depends on the cloud collector. The resolver's own comment (`HybridStreamProvider.swift:369-374`) acknowledges that "an absent `watch_discovery_started` record means the Watch gate suppressed the attempt". The direct fallback at `HybridStreamProvider.swift:766-770` ("registry_empty_direct_fallback") is therefore unreachable in exactly the scenario it exists for.
*Why it matters*: the owner's expected behaviour is "tap Watch, see the match". Today a correct live fixture can show "Check streams" or nothing, and tapping Check streams is the only way to run the adapter.
*Fix*: for a verified live/scheduled-within-lead fixture with at least one enabled optional provider that `supportsDiscovery(category:)`, always return `Action(evidence: .freshLookupOpportunity)`; let the resolver (which already has deadlines and cancellation) be the thing that says no. Make the registry and indexes *ranking* inputs, not admission inputs. Add a test: empty indexes + cached registry without the match + enabled CS → `action != nil`.

**B. Critical — Web-embed terminal failure skips the fresh resolver pass**
`Fotty/Features/Player/LivePlayerViewModel.swift:3258-3296`.
The branch that starts `exhaustedMatchLookup` (a fresh `LiveStreamResolver.resolvePlayback(..., refreshOptionalSources: true)`) requires `!isUsingWebEmbed`. Web sources are the default-enabled families. A web stall gets one reload (`.retryWebStall`), then `.exhaustSource`, then only `nextPlayableSource` among already-provided sessions; if none, `terminal_failure` at `:3300`.
*Fix*: drop `!isUsingWebEmbed` from the guard (the lookup is network-only and does not touch the WKWebView), or add a web-specific branch that runs the same lookup. Add a `LivePlayerRetryLifecycleTests` case: single web source, stall after decoded progress, expect `exhaustedMatchLookup != nil`.

**C. High — Startup buffer of 12 s on live HLS**
`Fotty/Features/Player/NativePlaybackPreparation.swift:62` sets `preferredForwardBufferDuration = 12` for every native item; `MultiLivePlayerView.swift:1485` uses `2.0`. For live HLS this pushes the player further behind live and lengthens time-to-first-frame, which the startup deadline then punishes. *Fix*: remove the override (let AVFoundation choose) or use ≤ 4 s for live; keep 12 s only for VOD/mp4 if ever needed.

**D. High — `NWPathMonitor` closure retains the view model strongly**
`LivePlayerViewModel.swift:1741`: `monitor.pathUpdateHandler = { path in Task { @MainActor in self.handle... } }`. The monitor is stored on `self` → cycle until `stopNetworkPathMonitoring()`. `cleanup()` does call it, but any pane that is dropped without `cleanup()` (e.g. a coordinator bug) keeps an `AVPlayer`, proxy and monitor alive. *Fix*: `[weak self]`.

**E. Medium — Audio interruptions and route changes only reconfigure the session**
`Fotty/Core/Media/MediaAudioSessionOwner.swift:304-322`. On `.ended` interruption and on route change the code calls `configureForPlaybackIfNeeded()` and nothing else; no `shouldResume` option check, no pause on headphone removal, no notification to the active `LivePlayerViewModel`. Playback state is reconciled indirectly via `timeControlStatus` KVO. *Fix*: route interruption/route-change events to the active pane and decide resume/pause explicitly; record them in quality details.

**F. Medium — Stall/watchdog loops are duplicated with different thresholds**
Watchdog (`:4138-4185`, 2 s tick, 2 or 6 stagnant ticks), stall validation (`:4199-4260`, 500 ms × 12 or 20), resume validation (`:1966-1994`, 8 s), continuity observer (`:4284`). Four independent timers reason about the same `currentTime()`. *Fix*: one `PlaybackProgressMonitor` type owning the sampling and emitting typed events; the policy enum decides.

**G. Medium — Now Playing artwork re-creates `MPMediaItemArtwork` on every update and never clears on web embed**
`Fotty/Core/Services/NowPlayingManager.swift:68-96`. Lock-screen controls work; the artwork is the app icon. Low impact, but `updateNowPlayingInfo()` is called from several transitions. *Fix*: cache the artwork once; include `MPNowPlayingInfoPropertyElapsedPlaybackTime` for live only if meaningful.

**H. Medium — PiP wiring is spread across a UIView subclass with mutable callbacks**
`Fotty/Features/Player/LivePlayerView.swift:365-600`. `dismantlePlaybackBinding()` stops PiP and detaches the layer; `deinit` only invalidates observers. Correct, but the `allowsPictureInPicture` setter dispatches to main from an already-main context (`:384`). Fine as is; simplify when the player view is refactored.

**I. Low — No cellular/Wi-Fi differentiation or peak-bitrate default**
Only `SinglePlaybackQualityPolicy` sets `preferredPeakBitRate` when the user picks a quality. `NWPathMonitor` already reports `isExpensive`; a cellular cap would reduce stalls on LTE. Low priority for a private app.

**J. Low — Legacy resolver still compiled**
`HybridStreamProvider.swift:46-123` (`actor HybridStreamProvider`) and `AnalyticalDataEngine.findStreams*` (`:410-540`) are a second resolution path with its own `withTimeout`. Confirm no caller, then delete.

No FairPlay/DRM is present; none is needed for the current sources.

### 2.2 Networking & fixture fetching

**A. High — 30-minute live-status freshness fence removes Watch silently**
`Fotty/Core/Models/SportsFixtureCatalog.swift:647-649`, `CurrentEventBroadcastPolicy.swift:286-290`. A `.live` fixture whose `observedAt` is older than 30 min fails `isLive(at:)`; `OptionalSourceLookupPolicy.event` returns `nil`; `FixtureSourceLookupPresentation.state` returns `nil`; the row loses both Watch and Check streams. Device refresh runs on scene-active and every 15 min (`MainTabView.swift:271-285`), so one failed sports lane during a match crosses the fence. *Fix*: treat a stale `.live` row as "live, unconfirmed" (still eligible for lookup, labelled honestly) until a *terminal* status arrives; surface the stale-feed condition in `catalogNotice`.

**B. Medium — `MatchListViewModel.refresh()` drops concurrent callers instead of joining**
`Fotty/Features/Dashboard/MatchListViewModel.swift:455-460`. `guard !isRefreshing else { return }` means a pull-to-refresh or scene-active `refreshIfNeeded()` that lands during an in-flight refresh returns immediately; the caller believes it refreshed. *Fix*: keep a `refreshTask: Task<Void, Never>?` and `await` it.

**C. Medium — Registry refresh cadence vs. live windows**
`BroadcastRegistry.swift:834` `refreshInterval = 300`, `refreshForPlayback` throttled to one call per 30 s, `FixtureCatalogAvailabilityIndex.minimumRefreshInterval = 300`. These are sane defaults for budget, but there is no "match I am watching" priority: the fixture on screen gets the same cadence as the rest of the day. *Fix*: a per-active-fixture lane with a 60 s cadence while a pane is open or a fixture is live and followed.

**D. Medium — Primary catalog decode uses `print`, `try?` and swallows mirror errors**
`AnalyticalDataEngine.swift:1001-1113` (`try? await fetchMatches`, `print("[LiveSports] …")`). Mirror failures never reach `FottyQualityStore`, so "catalog empty" cannot be distinguished from "all three mirrors failed" in the quality export. *Fix*: typed error per mirror, record once per refresh.

**E. Medium — `URLSession.shared` with per-request timeouts in football services**
`Fotty/Core/Providers/Football/FootballService.swift:228, 695, 711, 1647, 1663, 1691, 1739`. Mixed use of an injected session and `URLSession.shared`; `TeamNewsService` sets `waitsForConnectivity = true` (`:828`) which can hang a refresh lane for the full resource timeout on a flaky network. *Fix*: one injected session per service; `waitsForConnectivity = false` for anything the UI awaits.

**F. Low — Dead `LiveViewModel` with its own 5 s retry loop**
`Fotty/Features/Dashboard/LiveViewModel.swift` has zero references outside the file (verified by grep). Delete.

**G. Low — Date handling is correct**
Kickoffs are decoded as UTC `Date` and formatted at display time (`Date+LiveKickoffFormatting.swift`); fixture matchers use IANA zones for cricket day identity. No local-time parsing bugs found.

Offline UX: `NWPathMonitor` is only used inside the player. The dashboard shows a notice via `catalogNotice` but has no reachability input; a cold offline launch shows cached matches with no "offline" state until a fetch fails (UI test `testDashboardOfflineNoticeDoesNotHideMatches` exists). Acceptable.

### 2.3 Concurrency & memory

**A. High — `LivePlayerViewModel` fences ownership three different ways**
`loadRequestID` (UUID per attempt), `(sourceID, requestID, intentID)` tuples (`SingleNetworkRecoveryOwner`, `NativeItemFailureObservation`), and `stallValidationOwner` tokens. Each async continuation re-checks a different subset (`:2233-2237`, `:2908-2912`, `:4213-4218`). The rules are documented in comments and tests rather than enforced by a type. *Fix*: a single `AttemptHandle` struct captured at the start of every async branch, with one `isCurrent` method; make `loadCurrentSource` return it.

**B. Medium — Swift 6 isolation error already present**
`BroadcastRegistry.swift:732` references main-actor `freshness` from a nonisolated context ("error in Swift 6 language mode" in `logs/verify-latest.log`). 13 `@unchecked Sendable` conformances (`LocalStreamProxy`, `SharedEmbedRedirectDelegate`, `FottyImageCache`, etc.). Project is Swift 5.9 mode so it compiles today. *Fix*: fix the one error now; schedule a `SWIFT_STRICT_CONCURRENCY=complete` pass.

**C. Medium — Unstructured `Task {}` in views and coordinator**
`ViewingSessionCoordinator.swift:1253` (`Task { await cancelPlayback(request) }`), `:347`, `:618`, `:732`; `MultiLivePlayerView.swift` has 11 `Task {` sites; `SportsDashboardView.swift` 6. Most are fire-and-forget with generation checks inside, so not leaks, but none are cancellable from the owner. *Fix*: store or use `.task(id:)`.

**D. Medium — `Task.detached` in `BroadcastRegistryClient.prepare`**
`BroadcastRegistry.swift:1043-1055`. Detached decode of up to 4 MiB with cancellation handler — correct, but a `Task(priority:)` child would inherit cancellation for free. Low risk.

**E. Low — GCD remains in a few places**
21 `DispatchQueue` uses, mostly `.main.async` hops from KVO in `LivePlayerView.swift` and the audio-session serial queue (`MediaAudioSessionOwner.swift:66`), which is justified. `LocalStreamProxy` uses `NSLock` + a serial queue correctly; `deinit` (`:202-210`) reads `activeConnections` without the lock — harmless at deinit but inconsistent.

**F. Low — Retain-cycle review**
Timers: one (`MatchHubViewModel.swift:150`, weak self, invalidated in `deinit`). NotificationCenter tokens are stored and removed (`LivePlayerViewModel.swift:2916-2921`, `MediaAudioSession.observerTokens`). No `unowned`. One strong `self` capture found (§2.1-D).

**Incident-relevant concurrency path** (what could produce the owner's symptoms): the `.task(id: sourceCatalogTaskKey)` loop in `MainTabView` restarts whenever `enablementRevision` changes and is cancelled while the scene is inactive. On relaunch it awaits `BroadcastRegistryClient.shared.refresh(at:)` first (up to 20 s on a slow link, `:904`) before the CS catalog lane runs. During those seconds the Home row has no evidence and shows no Watch. If the user taps the row and opens Details, `checkOptionalSources` can run — but only if they know to.

### 2.4 Architecture & code quality

**A. High — God objects**
`LivePlayerViewModel.swift` 4,685 lines / ~60 stored vars; `HybridStreamProvider.swift` 2,230 lines (misnamed: it hosts `LiveStreamResolver`); `SportsDashboardView.swift` 2,504 lines, 38 `@State`, 272-line `body` (`:137-409`); `MultiLivePlayerView.swift` 2,128; `LiveWebEmbedPlayerView.swift` 2,264. *Fix*: see Phase C.

**B. Medium — Hidden singletons everywhere, DI by closure only at the leaves**
51 `static let shared` across 37 files. `LivePlayerViewModel.init` takes 15 injectable closures but the defaults reach `LiveStreamResolver.shared`, `MatchListViewModel.shared`, `FottyQualityStore.shared`. Tests work by injecting closures; production wiring is invisible. *Fix*: an `AppEnvironment` struct passed once from `FottyApp`.

**C. Medium — "Aspirational" architecture folders that are not wired**
`Fotty/Engine/*` (556 lines: `PlaybackEngine`, `SourceResolver`, `NativeStreamTransport`, `MatchIdentity`) are referenced only by tests and two type-name mentions; `Fotty/Core/Plugins` is a registry of 8 curated definitions, not plugins; `Core/Cloud`, `Core/Testing`, `Features/Social/Views` are empty directories. Folder names claim MVVM + engine layering; actual architecture is `@Observable` view models + a resolver actor + `@MainActor` policy enums. *Fix*: delete `Engine/` or make the resolver use it; remove empty dirs (they are generated by `generateEmptyDirectories: true`).

**D. Medium — Dead UI components**
`Design/Components.swift`: `HeroBanner`, `MediaCard`, `SkeletonCard`, `ShimmerView`, `ShareSheet`, `SectionHeader`, `PillButtonStyle`; `Design/Theme.swift`: `GlassBackground`, `BentoSurface`, `CardStyle`, `TactileGlassModifier`; `Design/UI/Animations.swift`: `GoalCelebrationView`, `SportCelebrationView` and the `SportMotion*` family — zero references outside their files. ~1,500 lines removable.

**E. Low — TODO/FIXME inventory: none.** `try!`: none. `as!`: one (`LivePlayerView.swift:520`, `layer as! AVPlayerLayer`, safe). `fatalError`: 6 (5 `init(coder:)`, 1 SwiftData in-memory fallback). 28 `print(` calls in production code (`AnalyticalDataEngine`, `FootballRepository`, `LiveViewModel`, `NotificationManager`, `MatchListViewModel`…) — replace with `Logger`. 27 empty `catch {}`; the ones in `HybridStreamProvider` and `LivePlayerViewModel` are deliberate cancellation sinks and are commented.

**F. Low — Hard-coded provider URLs and XOR "obfuscation"**
23 `URL(string:)!` literals for provider manifests/playlists (`PlavioSportsAddonClient.swift:138-148`, `ReviewedTVPlaylistClient.swift:10-13`, etc.). `StringObfuscator` (`Core/Security/StringObfuscator.swift`) XORs hostnames with a key that sits two lines above; the comment says it exists "to mask sensitive hostnames … from binary scanners". It provides no security and reads as review evasion (see §2.11). *Fix*: a single `ProviderEndpoints` struct, plain strings.

**G. Low — Naming drift**: `AnalyticalDataEngine` is the stream catalog client; `HybridStreamProvider.swift` hosts `LiveStreamResolver`; `Internal/` vs `Networking/` split is arbitrary; `MatchListViewModel` is the fixture catalog store.

### 2.5 UI layer

Reference: `docs/FOTTY-UI-DESIGN-STANDARD.md`. Source checks only; no visual verification was performed.

- **Medium — Heavy work in `body` paths**: `SportsDashboardView.body` builds derived catalogs through `@MainActor` policy enums (`CurrentEventBroadcastPolicy.IndexedCatalog`, `MatchStartPolicy`) per render; the project added `OSSignposter` categories for this (`Config.swift:7-11`), which suggests it has been measured. Keep the indexed-catalog memoisation; move it out of the view into `HomeProjectionCoordinator`.
- **Medium — Dynamic Type**: 36 fixed `.font(.system(size:))` uses, concentrated in `PlaybackControlsOverlay.swift` (9) and `LivePlayerView.swift` (6); 205 `dynamicTypeSize`/`@ScaledMetric` uses elsewhere. Player chrome will not scale. *Fix*: `.font(.system(size: 17, relativeTo: .body))` or text styles.
- **Low — Accessibility**: 534 accessibility label/identifier/hint sites; `FixtureSourceLookupPresentation` supplies labels and hints per state (`CurrentEventBroadcastPolicy.swift:366-376`). Good coverage.
- **Low — Dark Mode / appearance**: `FottyAppearance` with dark default and a Settings group, per the standard. Player chrome forced dark (`playback.md`). OK.
- **Low — Deprecated SwiftUI**: `.foregroundColor` ×10 (Settings and Dashboard components); `NavigationView`/`UIScreen.main`: none.
- **States**: loading/empty/error states exist for Home (`catalogNotice`), player (`transition(to: .failed …)`), source sheet. The *missing* state is the one in §2.1-A: a live fixture with no evidence shows "Broadcast unconfirmed" with hint "Availability updates automatically while Fotty is open", which is not actionable.

### 2.6 Persistence & state

**A. Medium-High — Multi-megabyte blob in `UserDefaults`**
`BroadcastRegistry.swift:7` (`maximumBytes = 4 MiB`), `:865` (read at init), `:978` (`defaults.set(encoded …)` on every successful refresh). `UserDefaults` is a plist owned by `cfprefsd`; every write rewrites the whole domain and the whole domain is loaded at launch. Also inflates the private-backup export surface. *Fix*: write to `Caches/BroadcastRegistry/accepted.json` with atomic replace; keep only `revision`/`generatedAt` in defaults.

**B. Low — Bounded stores are correctly bounded**
`FottyQualityStore`: 250 records / 14 days, allow-listed keys (`FottyLogger.swift:433-478`). `LiveSourceHealthStore`: 12 startup samples. `FottyImageCache`: 600 / 32 MiB. `LastLiveMatchStore`, `MatchReminderStore`: small.

**C. Low — Key naming is inconsistent**: 24 distinct defaults keys across four prefixes (`fotty.*`, `settings.*`, `sports.*`, `com.fotty.*`). Collect into one `DefaultsKey` enum.

**D. Low — Nothing sensitive in `UserDefaults`.** The FPL coach access code and the sync writer origin are in Keychain with `AfterFirstUnlockThisDeviceOnly` (`FPLCoachAccessStore.swift:33-75`, `SportsPreferenceSync.swift:216-250`). Keychain survival across reinstall is handled (`:39-44`).

**E. Low — SwiftData fallback**: `LocalDataStore.swift:40-74` falls back to in-memory and flags `isUsingVolatileFallback`; callers check it. `fatalError` only if even that fails. Acceptable.

### 2.7 Security & privacy

- **Good**: no API keys in source; `Info.plist` keys are build-setting placeholders that resolve to empty and disable the direct football APIs (`Config.swift:71-83`). Worker proxies hold the real secrets. ATS: arbitrary loads off, local networking on (required for the loopback relay), WebKit arbitrary loads off. `WKWebsiteDataStore.nonPersistent()`. Relay binds `127.0.0.1` on an ephemeral port, validates destinations (public-IP preflight, same-origin cookies, redirect limits, byte caps) (`LocalStreamProxy.swift:117-160, 520-540`). Diagnostics strip query/fragment (`HybridStreamProvider.swift:2219`).
- **Medium — Required-reason API not declared**: `ProcessInfo.processInfo.systemUptime` is used in 9 files (`LocalStreamProxy`, `MultiLivePlayerView`, `CNCSportsAddonClient`, `FottyImagePipeline`, …). This is `NSPrivacyAccessedAPICategorySystemBootTime`; `Fotty/Resources/PrivacyInfo.xcprivacy` declares only `UserDefaults` (CA92.1). App Store Connect will warn or reject. *Fix*: add the category with reason `35F9.1`, or switch to `ContinuousClock`/`DispatchTime` (which are not required-reason).
- **Low — `print` logging** carries provider labels and fixture ids, not URLs or tokens. `Logger` calls use `privacy: .public` only for enums/bools. OK.
- **Low — No certificate pinning.** Not warranted for third-party aggregators that rotate hosts.
- **Low — The XOR obfuscator** is not a security control (§2.4-F).

### 2.8 Performance

**A. Medium-High — Launch / foreground work fan-out**
`MainTabView.swift:231-285` starts three loops on `.active`: registry refresh + catalog collector every 60 s, provider preflight on a schedule, fixture refresh every 15 min. The registry path decodes/validates/indexes/re-encodes up to 4 MiB (`BroadcastRegistry.swift:1043-1055`) and the comment at `:904` records ~12 s observed. On an 8 GB dev Mac this is invisible; on an older iPad it competes with the first Home render. *Fix*: file-backed snapshot (§2.6-A); skip re-encoding when `revision` unchanged; start the collector after first frame.

**B. Good — Image pipeline** (`FottyImagePipeline.swift`): request coalescing, 2 MiB cap with streaming cut-off, 2-way decode concurrency, 2 s negative cache, URLCache 48 MiB disk. No changes needed.

**C. Low — Asset catalog**: `AppIcon1024.png` 1.1 MB; three `stadium_*.png` at ~1 MB each with one code reference; `Fotty/Assets/Fallbacks` 5.5 MB (duplicates of the stadium PNGs, referenced by the pbxproj group only). Re-export as HEIC/compressed PNG or drop the duplicates: ~6-7 MB off the IPA.

**D. Low — Polling timers in the player** (2 s watchdog, 500 ms stall sampler) are fine; consider `AVPlayerItem` periodic time observer to avoid the busy loop.

### 2.9 Build, tooling, hygiene

- **Warnings (from `logs/verify-latest.log`, Xcode 27.2 / 27B52)**: 108 lines, deduplicated to ~40 unique sites: ~30 "no async operations within await" (`ReviewedTVPlaylistClient.swift:226,232,318,325`, `CommunitySportsAddonClient.swift:268,275`), ~15 "backward matching of trailing closure" (`MatchListViewModel.swift:647`, `FootballModels.swift:596`, several tests), ~14 Catalyst `UIWindow(frame:)` deprecations in `NativeFullscreenPlaybackTests`, one Swift-6 isolation error (§2.3-B), one unused result (`MainTabView.swift:238`), three test `Sendable` conformance warnings, one "immutable property will not be decoded" (`SourceConnectionToolTests.swift:108-110`). All fixable in an afternoon.
- **SwiftLint / SwiftFormat**: both installed (`/opt/homebrew/bin`), neither configured (`.swiftlint.yml`, `.swiftformat` absent) nor run in CI. I would start with `swiftlint lint --reporter summary` using a minimal config (`line_length: 160`, `file_length` warning 1500, `type_body_length` warning 800, `function_body_length` warning 120, disable `todo`), and `swiftformat --lint Fotty --swiftversion 5.9`.
- **Project settings**: `project.yml` is source of truth (good, `tools/verify-native-version.rb` checks drift). `LastUpgradeCheck = 1430` (Xcode 14.3) in a project built with Xcode 27. Project-level configs say `SWIFT_VERSION = 5.0` (`project.pbxproj:2342,2446`) while targets say 5.9 — harmless but misleading. Deployment target iOS 26.4 forces CI onto a `xcode-27` runner with a Catalyst override to 26.1 (`ios.yml`, `tools/ios-ci.sh:22-32`) — fragile until that runner image catches up.
- **`.gitignore`**: ignores `*.lock` and `*.txt` globally. `web/package-lock.json` is tracked so it survived, but any future lockfile or `.txt` doc is silently untracked. Narrow these.
- **Localization**: none (`0` `.strings`/`.xcstrings`); all copy is inline English. Acceptable for a private app, blocks any store listing beyond en-US.
- **CI**: Catalyst-only logic tests + unsigned iOS Release build (`tools/ios-ci.sh:91-140`), with retired-vocabulary grep (`:78-89`). UI tests (96 functions, 46 in `PlaybackPerformanceUITests`) are device-only and never run in CI. `tools/claude-verify.sh` reproduces CI locally with log retention — good.
- **Repo hygiene**: `_to_delete/`, `scratch/`, `backups/`, `IconDrafts/`, `stream_test_output.png` at the root (all gitignored); 65 scripts in `tools/` with several overlapping audit-* families. `README.md` points at `docs/Fotty-Developer-Handoff.md` which exists and is current.

### 2.10 Testing

- **Volume**: 92 unit files, 5 UI files, ~2,800 `func test` (2,652 pass / 12 skip in the 244 release gate). 127 `XCTSkip` sites, mostly physical-device gates.
- **Shape**: overwhelmingly policy/ownership tests driven through injected closures (`PlaybackPolicyTests` 5,404 lines, `ViewingSessionCoordinatorTests` 3,880, `CommunitySportsAddonTests` 3,490). They assert the guards described above, which is why incidents pass tests: the guards are the specification.
- **Untestable as written**: real `AVPlayer` behaviour (Catalyst can't decode provider HLS in CI; one opt-in soak test exists), `WKWebView` embed lifecycle, `NWPathMonitor`, PiP, Now Playing. The 60 s / 300 s index lifetimes are tested with injected clocks, but there is **no test that drives `CurrentEventBroadcastPolicy.action` from an empty process state through the resolver to a published session** (searched for cold/reopen/relaunch tests: 8 hits, none cover this path).
- **Highest-value tests to add**:
  1. Cold start: empty `FixtureStreamDiscoveryIndex` + registry snapshot without the fixture + enabled CS + live fixture → `action(for:)` non-nil → `resolvePlayback` reaches `direct_fallback_lookup`.
  2. Web-embed terminal stall after decoded progress → fresh lookup task is started (§2.1-B).
  3. `.live` fixture with `observedAt` 31 min old → still eligible for lookup once §2.2-A is fixed.
  4. `MatchListViewModel.refresh()` concurrent callers both observe the completed refresh (§2.2-B).
  5. `BroadcastRegistryClient` snapshot round-trip through the file store (after §2.6-A).
  6. A contract test that replays the redacted `docs/testing/fotty244-leeds-discovery-2026-11-07/investigation.json` shapes through `CommunitySportsAddonClient.catalogMatches` and `selectMatch` (the handoff already proved the cloud side; the native side has no replay).

### 2.11 App Store / compliance

- `PrivacyInfo.xcprivacy`: tracking false, UserID/DeviceID/OtherUserContent declared as linked, app-functionality purpose. **Missing** `SystemBootTime` required-reason entry (§2.7). No third-party SDKs, so no SDK manifests needed.
- Usage descriptions: none required (no camera/mic/location/photos). Notifications via `UNUserNotificationCenter` need no plist key. Background modes `audio` + `fetch` with `BGTaskSchedulerPermittedIdentifiers` declared; `NSSupportsLiveActivities(FrequentUpdates)` declared; app group + iCloud KVS entitlements consistent between app and extension.
- **Review-sensitive**: the app's default-enabled sources are web-embed aggregators (`embed.st`, `streamed.pk`, `score808live.tv`, `vipleague.im`, `streamex.net` appear as literals or XOR-encoded in `AnalyticalDataEngine.swift:366-615`), and `StringObfuscator`'s stated purpose is to hide them from binary scanners. For a private TestFlight group this is the owner's call; for any App Store submission it is a guideline 5.2.3 / 1.1 problem that obfuscation makes worse, not better. `tools/ios-ci.sh:78-89` already greps out retired "review-safe" vocabulary, so the project is aware of the boundary. Stated plainly for the record; no recommendation beyond keeping the distribution scope explicit.
- Legal URLs point at `getfotty.com`, which Current-State says is unavailable.

---

## 3. Prioritised plan

Effort: **S** < ½ day, **M** 1-3 days, **L** > 3 days. All phases are source-only until the owner names a device gate.

### Phase A — Stability: playback and fixtures (do first)

| # | Change | Effort | Depends on |
|---|---|---|---|
| A1 | Remove `!isUsingWebEmbed` from the exhausted-lookup guard (`LivePlayerViewModel.swift:3262`); add the retry-lifecycle test | S | — |
| A2 | `CurrentEventBroadcastPolicy.actionForCurrentEvent`: return `.freshLookupOpportunity` for any verified live / within-lead fixture that has an enabled discovery-capable provider, independent of index/registry state; keep indexes for ranking and the label | M | — |
| A3 | Treat stale `.live` (`observedAt` > 30 min) as "live, unconfirmed": eligible for lookup, label says feed is stale; surface stale-fixture notice on Home | M | A2 |
| A4 | Active-fixture priority lane: while a pane is open or a followed fixture is live, poll that fixture's enabled providers every 60 s instead of 300 s; cancel on dismiss | M | A2 |
| A5 | `MatchListViewModel.refresh()` joins the in-flight task instead of returning | S | — |
| A6 | Drop `preferredForwardBufferDuration = 12` for live HLS | S | — |
| A7 | Add the six tests from §2.10 (cold start first) | M | A1-A3 |
| A8 | Quality export: add `watch_gate_suppressed` record when `action(for:)` returns nil for a live fixture with enabled providers, so the next incident is diagnosable from `fotty.quality.records.v1` | S | — |

### Phase B — Memory, concurrency, error handling

| # | Change | Effort | Depends on |
|---|---|---|---|
| B1 | `[weak self]` in `NWPathMonitor` handler; audit the other 20 `Task {` sites in player/coordinator for cancellation ownership | S | — |
| B2 | Introduce `AttemptHandle` (sourceID, requestID, intentID, item) and one `isCurrent()`; replace the three fencing schemes incrementally, starting with the network-recovery and stall paths | L | A1 |
| B3 | Route audio interruption / route-change to the active pane; explicit resume/pause policy; record in quality details | M | — |
| B4 | Fix the Swift-6 isolation error at `BroadcastRegistry.swift:732`; run one `SWIFT_STRICT_CONCURRENCY=complete` build and triage | M | — |
| B5 | Replace 28 `print` with `Logger`; record mirror failures in `AnalyticalDataEngine` as typed quality events | S | — |
| B6 | One injected `URLSession` per football service; `waitsForConnectivity = false` on UI-awaited paths | S | — |
| B7 | Move the registry snapshot from `UserDefaults` to a Caches file with atomic write; skip re-encode when revision unchanged | M | — |

### Phase C — Architecture and cleanup

| # | Change | Effort | Depends on |
|---|---|---|---|
| C1 | Split `HybridStreamProvider.swift`: `LiveStreamResolver.swift`, `OptionalSourceLane.swift`, `SharedCatalogLane.swift`, `DiscoveryQualityReceipts.swift`; delete legacy `actor HybridStreamProvider` and `AnalyticalDataEngine.findStreams*` after confirming no callers | M | — |
| C2 | Extract from `LivePlayerViewModel`: `PlaybackProgressMonitor` (watchdog/stall/resume/continuity), `NativeHandoffController`, `PictureInPictureController`, `WebEmbedController`; the view model keeps state + transitions | L | B2 |
| C3 | `SportsDashboardView`: move derived catalogs into `HomeProjectionCoordinator`; split into section views; target ≤ 600 lines | M | — |
| C4 | Delete dead code: `LiveViewModel`, `Engine/*` (or wire it), unused `Design/*` components (§2.4-D), empty directories | S | — |
| C5 | `AppEnvironment` composition root in `FottyApp`; retire `.shared` from the player/resolver/catalog path first | L | C1, C2 |
| C6 | `ProviderEndpoints` struct replacing 23 force-unwrapped URL literals and `StringObfuscator` | S | — |

### Phase D — Polish, tests, tooling

| # | Change | Effort | Depends on |
|---|---|---|---|
| D1 | Clear the 40 unique compiler warnings | S | — |
| D2 | Add `.swiftlint.yml` + `.swiftformat`, run in `tools/ios-ci.sh` (lint only, non-blocking first) | S | — |
| D3 | Player chrome Dynamic Type (`PlaybackControlsOverlay`, `LivePlayerView`) using `relativeTo:` | S | — |
| D4 | `PrivacyInfo.xcprivacy`: add `SystemBootTime` 35F9.1, or migrate `systemUptime` to `ContinuousClock` | S | — |
| D5 | Assets: compress AppIcon/stadium PNGs, drop `Assets/Fallbacks` duplicates | S | — |
| D6 | `.gitignore`: remove global `*.lock`/`*.txt`; `LastUpgradeCheck` bump via XcodeGen; project-level `SWIFT_VERSION` 5.9 | S | — |
| D7 | Consolidate `UserDefaults` keys into one enum | S | — |

---

## 4. Quick wins (≤ 15 minutes each)

1. `LivePlayerViewModel.swift:1741` → `{ [weak self] path in Task { @MainActor in self?.handleNetworkReachabilityChange(…) } }`.
2. `LivePlayerViewModel.swift:3262` → remove `!isUsingWebEmbed` (then run `LivePlayerRetryLifecycleTests`).
3. `NativePlaybackPreparation.swift:62` → delete the `preferredForwardBufferDuration = 12` line.
4. `BroadcastRegistry.swift:732` → make `freshness` `nonisolated static let` (it is a constant).
5. `MainTabView.swift:238` → `_ = await BroadcastRegistryClient.shared.refresh(at: now)`.
6. `MatchListViewModel.swift:647` and `FootballModels.swift:596` → label the trailing closure `status:`.
7. `ReviewedTVPlaylistClient.swift:226,232,318,325`, `CommunitySportsAddonClient.swift:268,275` → drop the redundant `await`.
8. `PrivacyInfo.xcprivacy` → add `NSPrivacyAccessedAPICategorySystemBootTime` / `35F9.1`.
9. Delete `Fotty/Features/Dashboard/LiveViewModel.swift` (zero references); run `tools/check_native_source_membership.py` and regenerate with XcodeGen.
10. `.gitignore` → replace `*.lock` with `Podfile.lock` (or remove) and delete `*.txt`.
11. `MatchListViewModel.refresh()` → store `refreshTask` and `await` it when `isRefreshing`.
12. Add `swiftlint lint --quiet --reporter summary` as a non-blocking step at the end of `tools/claude-verify.sh`.

---

## 5. Open questions for the owner before refactoring

1. **Which providers are enabled on the incident iPad?** CS/AS/LS/FS/SV/TV all default OFF (`StreamPlugin.swift:256-270`). If only the web families were on, §2.1-B alone explains both symptoms and A2/A3 matter less for that device. The quality export (`fotty.quality.records.v1`) answers this without touching the phone.
2. **Should a live fixture with an enabled provider *always* show Watch** (resolver decides), or must the row stay honest-but-passive until some evidence exists? A2 assumes the former; the design standard's "distinction between scheduled and watchable" could be read either way.
3. **Is the cloud registry a gate or a hint for native?** The 8 Nov Decisions-Log entry says native still "uses direct fallback only when the registry is empty" and defers the hint model. A2/A4 implement the hint model; confirm that is the intent before touching `resolveOptionalSports`.
4. **Half-time semantics**: `FootballMatch.MatchStatus.isLive` includes `.paused` (HT). Should a *web* stall at HT trigger failover immediately, or wait (e.g. 90 s) because many provider embeds pause at the break? A1 makes failover possible; the delay is a product decision.
5. **Distribution scope**: is any App Store submission planned? If yes, §2.11 (sources, obfuscator, privacy manifest, localization, legal URLs) becomes Phase A work; if the app stays private TestFlight, it stays Phase D.
6. **Appetite for the god-object split (C2, L effort)**: it is the only change that reduces the rate of new incident guards, but it is also the riskiest to land without device time. A staged approach (B2 first, behind the existing tests) needs the owner's agreement to a multi-week source-only track before a device gate.
7. **Swift 6 / strict concurrency**: do you want the codebase moved to Swift 6 language mode this cycle (B4 scope grows to M-L), or only the one current error fixed?
8. **Engine folder**: delete, or is it an intended destination for the resolver?

---

*Method*: every Swift file was enumerated and line-counted; the eleven key files named in the brief were read in full or in their decision paths; the remaining 200 files were swept with pattern searches (AVPlayer/KVO/observers, `Task`, GCD, timers, singletons, force operators, `print`, empty `catch`, `UserDefaults`/Keychain, URLs, deprecated APIs, required-reason APIs) and spot-read where a hit warranted it. `logs/verify-latest.log` (Catalyst tests + iOS Release build, 19:45 local) supplied the warning inventory. Nothing was executed or modified.
