# Fotty Apple Platform Baseline

Last reviewed: 2026-09-06

This is the living compatibility and release checklist for Fotty Sports Hub.
It is an engineering gate, not a substitute for App Review, legal advice, or
hands-on acceptance on every supported device. Every significant feature or
release change should update the relevant status below and link its evidence.

For UI work, also use [Fotty's UI design standard](FOTTY-UI-DESIGN-STANDARD.md)
(added 2026-09-19). It adds Apple HIG review, a native design contract and explicit
visual/interaction evidence; the engineering gates here do not certify appearance.

## Status vocabulary

- **Green** — source and automated evidence are current; physical or release
  evidence is recorded where the item requires it.
- **Amber** — the current design is intentional, but the next audit or device
  gate is still required.
- **Open** — a known gap, migration, or review decision remains.

## Baseline gates

| Area | Current status | What must remain true | Current evidence / next gate |
| --- | --- | --- | --- |
| SwiftUI update cost | Amber | View bodies stay cheap; business logic and network work stay out of `body`, row initializers, and high-frequency callbacks. Large catalogs use stable lazy children and precomputed projections. | `SportsDashboardView`, `HomeSportsDiscovery`, and `SportsDiscoveryViews` follow this boundary. Profile cold and warm Home/Search with the SwiftUI Instruments template and record hitch evidence before declaring the stutter fixed. |
| Scroll containers and layout | Green/Amber | Use `LazyVStack`/`LazyHStack` only where profiling shows a benefit; avoid nested lazy stacks, dynamic child counts, absolute offset restoration, and layout/state feedback loops. | Build 70 release record and `BetaUsabilityTests.testCatalogScrollUsesStableLazyRowsWithoutAbsoluteOffsetTracking`. Physical cold-scroll acceptance remains required. |
| Observation | Amber | A view should invalidate only for observable properties it reads. Prefer the Observation macro for new models; migrate `ObservableObject` incrementally without mixing wrappers incorrectly. | Current source intentionally mixes `@Observable` and legacy `ObservableObject`. Do not perform a wholesale migration during a playback or release fix. Track remaining types and migrate one bounded owner at a time. |
| Swift concurrency | Open | No data races, unsafe shared mutable state, or unchecked delegate crossings. Delayed work must be cancellable and keyed to the current source/attempt. | A full Swift 6 diagnostic previously exposed real WebKit/AVKit/shared-state isolation work. Keep Swift 5.9 for this cycle; enable complete concurrency checking in a separate audit configuration and close one owner at a time. |
| Playback audio and PiP | Amber | Configure `AVAudioSession` for playback, activate only when playback begins, preserve the active attempt through scene changes, and keep native PiP/background playback owned by the player. | `MediaAudioSession`, `LivePlayerViewModel`, `LivePlayerView`, and `LiveWebEmbedPlayerView` implement the policy. Physical iPhone/iPad native handoff, app switch, lock/unlock, and duplicate-audio checks remain required. |
| WebKit media configuration | Amber | Create each `WKWebViewConfiguration` before the web view; set inline/PiP/user-action policy deliberately; keep provider-origin navigation and touch handling isolated. | `LiveWebEmbedPlayerView` enables inline/PiP and leaves provider controls canonical. Recheck provider controls and PiP after WebKit/Xcode upgrades. |
| Transport security / ATS | Implemented | Keep `URLSession` on ATS-protected HTTPS; never bypass certificate failures, downgrade a source, or restore an arbitrary proxy. | `Fotty/Info.plist` sets `NSAllowsArbitraryLoadsInWebContent = NO`. Shared catalog admission and WebKit navigation both restrict playback to reviewed HTTPS origins. |
| Privacy manifest | Amber | `PrivacyInfo.xcprivacy` contains only accurate collected-data and required-reason declarations, and the archive privacy report matches App Store Connect disclosures. | The manifest is bundled and plists validate. Generate an archive privacy report before the next distribution candidate and reconcile it with the iOS Privacy screen and App Store Connect answers. |
| Notifications and Live Activities | Amber | Ask for notification authorization in context, read current notification settings before scheduling, use truthful payloads, and stop/remove Live Activities on completion or explicit dismissal. | `MatchReminderStore`, `NotificationManager`, and `FottyLiveActivityController` own this behavior. Add a physical locked-device delivery/tap/force-close check to the beta gate. |
| Accessibility | Amber | Preserve Dynamic Type, VoiceOver labels/traits, 44-point interaction regions, sufficient contrast, Reduce Motion, and Reduce Transparency behavior. | Source contracts and Catalyst checks exist. Repeat iPhone/iPad checks at large text, Reduce Motion, VoiceOver, light/dark appearance, and landscape before a wider beta. |
| Images and remote artwork | Green/Amber | Downsample off the main actor, coalesce duplicate requests, cancel work for disappearing rows, bound memory/disk caches, and keep truthful fallbacks. | `FottyImagePipeline`, `FottyImageDecoder`, and `TeamBadgeWindow` implement the current boundary. Monitor cache size and cold-scroll hitches after provider/catalog changes. |
| Data and persistence | Amber | SwiftData writes are owned away from active scrolling; stale/partial feeds fail safely; backups exclude credentials, provider URLs, Coach text, and diagnostics. | `MatchCatalogCacheWriter`, `LocalDataStore`, and private-backup tests cover the policy. Files restore and partial-feed physical acceptance remain open. |
| Testing and measurement | Amber | Maintain the test pyramid: fast unit tests, focused integration/contract tests, a small number of UI journeys, and repeatable performance metrics. Do not treat a compile or process hold as UI/playback proof. | `tools/ios-ci.sh` is simulator-free and green. Add a bounded performance test/trace baseline for Home cold scroll and launch; retain physical-device acceptance for playback and accessibility. |
| Release hygiene | Green/Amber | Use one monotonic Apple build number, archive with an Apple-supported Xcode, distinguish upload/processing/TestFlight availability/installation, and remove temporary DerivedData, archives, traces, and logs. | `docs/RELEASE-PROCESS.md` and the CI/performance scripts encode this. Keep TestFlight for significant milestones; use private cable installs only for explicitly requested pre-tests. |

### Current strict-concurrency diagnostic

On 2026-09-06, a read-only generic iOS compile with
`SWIFT_STRICT_CONCURRENCY=complete` completed after the FPL manager lookup
closure was explicitly isolated to `@MainActor`. The diagnostic still reports
real migration work in the Live Activity widget, AVPictureInPicture delegate,
notification delegates, shared caches, provider/repository crossings, and
non-Sendable model boundaries. These are tracked as migration work, not
suppressed with `@preconcurrency` or a project-wide Swift 6 switch. The normal
Swift 5.9 simulator-free gate remains the release gate until those owners are
migrated and physically requalified. The lock-guarded date formatter cache was
also migrated without changing its synchronous call sites; its prior
`RelativeDateTimeFormatter` concurrency warning is now clear.

## Required review sequence for future work

1. Identify which baseline rows the change touches before editing code.
2. Run the relevant source-contract and unit tests first.
3. Profile any UI/performance change with the SwiftUI Instruments template on a
   physical device; use signposts and hitch metrics rather than impressions.
4. Run the simulator-free Catalyst suite and generic iOS Release build.
5. For playback, notifications, accessibility, or persistence, perform the
   corresponding physical iPhone/iPad acceptance step.
6. For a distribution candidate, generate the privacy report, verify ATS and
   entitlements, then record Apple upload, processing, TestFlight assignment,
   installation, and tester feedback as separate states.

## Official Apple references

- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)
- [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app/)
- [Migrating from `ObservableObject` to the Observation macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Adopting strict concurrency in Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6)
- [Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
- [`WKWebViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration)
- [App Transport Security](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity)
- [`NSAllowsArbitraryLoadsInWebContent`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing use of required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Testing](https://developer.apple.com/documentation/xcode/testing)
- [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)
