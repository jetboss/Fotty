# Fotty platform modernization audit — 2026-08-29

## Outcome

Fotty now uses StoreKit's signed app transaction instead of an App Store receipt
filename to distinguish internal TestFlight/Xcode builds from public App Store
builds. The web and Worker toolchain also received a compatible current-version
upgrade and reports zero npm vulnerabilities. Large platform migrations that
touch playback or distribution reach were measured, not enabled blindly.

No app version/build number, device install, TestFlight upload, Worker deploy,
paid model request, or simulator run is part of this work.

## Implemented now

### Signed StoreKit distribution detection

- `DistributionEntitlementPolicy` reads `AppTransaction.shared` and accepts only
  StoreKit-verified `.sandbox` or `.xcode` environments for internal access.
- `.production`, an unverified transaction, an unavailable transaction, or an
  error all fail closed to the public review-safe surface.
- Debug remains available immediately. A normal Release starts safely and
  resolves StoreKit asynchronously at launch, retrying when the app becomes
  active.
- The result is process-local. No entitlement is persisted for a later public
  build to inherit. Obsolete `is_pro_user` and old review-mode state are removed.
- Normal Release no longer honors persisted or environment distribution-mode
  overrides. Debug retains its development override; Review Safe remains a
  compile-time boundary.

Apple references:

- <https://developer.apple.com/documentation/storekit/apptransaction>
- <https://developer.apple.com/documentation/storekit/apptransaction/shared>
- <https://developer.apple.com/documentation/storekit/verificationresult>

### Current concurrency primitive for the release gate

The small process-local review-mode state now uses `Synchronization.Mutex`
instead of an unsafe mutable static plus a manually paired `NSLock`.

Reference: <https://developer.apple.com/documentation/synchronization/mutex>

### Web and Worker dependency baseline

| Area | Previous | Current |
| --- | --- | --- |
| Next.js | 16.2.6 | 16.3.3 |
| React / React DOM | 19.2.4 | 19.2.8 |
| Motion | 12.38.0 | 13.1.1 |
| HLS.js | 1.6.16 | 1.7.1 |
| Lucide React | 1.8.0 | 1.37.0 |
| Tailwind CSS/PostCSS | 4.2.4 | 4.3.3 |
| Playwright | 1.60.0 installed | 1.62.1 |
| Wrangler | unpinned through `npx` | 4.127.1 pinned |
| Node production image | 22 | 24 LTS |
| TypeScript output target | ES2017 | ES2022 |
| npm audit | four high-severity production-tree findings initially | zero vulnerabilities |

The package now declares its Node/npm baseline, includes `.nvmrc`, and has a
repeatable `npm run worker:check` dry-run. Wrangler local state is ignored.
The Worker compatibility date is 2026-08-29. The new automatic Node runtime
compatibility flags are explicitly disabled because this Worker does not need
them; this updates runtime fixes without silently changing its execution model.

Cloudflare references:

- <https://developers.cloudflare.com/workers/configuration/compatibility-dates/>
- <https://developers.cloudflare.com/workers/wrangler/commands/workers/>

### Build configuration cleanup

The obsolete `ENABLE_BITCODE = NO` setting is removed from the XcodeGen source
and generated project. Apple no longer accepts bitcode submissions, so carrying
the retired switch adds no value.

## Measured migrations, deliberately not enabled yet

### Swift 6 strict concurrency

A full Swift 6 / complete-concurrency build fails in the current source. A Swift
5 targeted-concurrency build succeeds but reports warnings in these ownership
areas:

- WebKit JavaScript values crossing task boundaries
- WebKit and AVKit delegate isolation
- notification delegate isolation
- local stream proxy `@Sendable` captures
- legacy match-discovery shared state
- SwiftData predicate key paths
- shared log, formatter, audio-observer and cache state
- one generic timeout helper without a `Sendable` result constraint

This is a real reliability program, especially for playback, and should be done
incrementally with targeted concurrency enabled per cleaned module. Apple
explicitly supports incremental migration rather than a one-shot language-mode
change.

References:

- <https://developer.apple.com/documentation/swift/adoptingswift6>
- <https://www.swift.org/migration/>

### iOS deployment reach

The project currently requires iOS/iPadOS 26.4. A clean unsigned Release build
with `IPHONEOS_DEPLOYMENT_TARGET=18.0` succeeds, proving the source does not
currently require 26.4 at compile time. Lowering the checked-in target would let
many more testers install Fotty while still compiling with the newest SDK and
using new APIs behind availability checks.

This was not changed because it expands the supported-device and QA matrix and
needs an explicit product decision. Recommended baseline: iOS/iPadOS 18.0,
followed by one iOS 18 physical-device smoke and the existing current-OS gates.

### TypeScript 7 and ESLint 10

- TypeScript 7 is current, but Microsoft documents that 7.0 does not ship the
  compiler API consumed by current tooling. Its TypeScript 6 bridge package was
  tested; Next 16.3 rejected the aliased package identity. Fotty therefore stays
  on TypeScript 5.9 until Next supports the transition.
- ESLint 10 was tested. Next's bundled import, React and accessibility plugins
  still declare ESLint 9 peer support, leaving an invalid tree. Fotty therefore
  stays on ESLint 9.39.5 until that peer set advances.

References:

- <https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/>
- <https://eslint.org/docs/latest/use/migrate-to-10.0.0>

## Highest-value current Apple opportunities

1. **Hybrid on-device FPL Coach.** Prototype the Foundation Models framework as
   an optional explanation layer on supported devices, retaining deterministic
   FPL scoring/rules as truth and the Worker/DeepSeek route for larger context or
   unsupported devices. This could reduce latency, cost and data transfer, but
   prompt/evaluation work is mandatory because Apple's installed model changes
   with OS updates.
2. **Swift 6 concurrency migration.** Clean the warning groups module by module,
   starting with non-playback caches and services, then WebKit/proxy code with
   focused continuity gates. This offers more reliability value than cosmetic
   framework churn.
3. **SwiftUI WebKit proof of concept.** Apple's `WebView`/`WebPage` APIs provide
   observable navigation and JavaScript from SwiftUI. Build a parity spike for
   one provider, but do not replace the current player until popup blocking,
   provider controls, decoded-playback monitoring, custom headers, pause/resume,
   failover and PiP behavior all match.
4. **App Intents.** Expose a small set of user-owned actions—open Matchday, open
   FPL, and view the next saved broadcast—to Siri, Spotlight and Shortcuts. Do
   not create a background live-score promise the system cannot guarantee.
5. **Lower the deployment target after approval.** This is the fastest way to
   increase beta reach without giving up the newest SDK on current devices.

Apple references:

- <https://developer.apple.com/documentation/foundationmodels>
- <https://developer.apple.com/documentation/webkit/webkit-for-swiftui>
- <https://developer.apple.com/documentation/appintents>

## Verification record

- StoreKit environment policy focused Catalyst test: pass.
- Normal generic iOS Release with the current target: pass.
- Diagnostic generic iOS Release at an iOS 18.0 target: pass.
- Swift 5 targeted-concurrency diagnostic: builds with the warning groups above.
- Swift 6 complete-concurrency diagnostic: expected failure; no language-mode
  change was committed.
- Worker Wrangler 4.127.1 dry-run: pass; no deployment.
- npm production/full audit after upgrades: zero vulnerabilities.
- Web unit suite: 86/86 pass.
- Web lint: zero errors and 93 existing warnings, concentrated in unused values
  and React effect-state patterns; these remain cleanup work rather than a
  release-gate failure.
- Next.js 16.3.3 production build and TypeScript check: pass.
- Final no-simulator Catalyst suite: 220 executed, one existing opt-in HLS test
  skipped, zero failures (219 passes).
- Normal and Review Safe generic iOS Release builds: pass. The only remaining
  build warning is the expected App Intents metadata notice because Fotty has not
  yet added an App Intents target dependency.
- All owned Xcode and Wrangler temporary output was removed after verification.
