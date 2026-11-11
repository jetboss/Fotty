# Fotty 2.0.1 (127) private iPad performance update

Date: 2026-10-10. This update implements the approved whole-app performance and
playback improvements, with private testing on Jet iPad. Shared TestFlight121,
owner phones125 and production backend remain unchanged. FPL feature work is
paused. No packages, paid services or telemetry uploads were added.

## Changes

1. Bound native HTTP response sizes, deadlines and redirects. Cancellation stops
   the underlying request; malformed catalog bodies are not accepted as empty feeds.
2. Require advancing decoded native frames before an automatic WebKit-to-native
   handoff. Ready or loaded states alone do not establish playback.
3. Preserve Watch Two playback through inactive transitions; true background
   handling and a bounded native retry respect the selected attempt and user pause.
4. Validate CS redirects before following them, with bounded responses and hops.
5. Give each visible score consumer its own polling lease so a hidden surface
   cannot cancel another consumer's polling.
6. Recheck resident badge-cache freshness and retry failed refreshes without
   falsely renewing their receipt.
7. Publish usable provider and fixture results independently. Unchanged or rejected
   fixture receipts avoid duplicate catalog merges; changed receipts still publish.
8. Prepare Search's normalized index once per accepted revision and publish only
   current query results. Empty queries need no index; preparation yields in batches.
9. Cache parsed kickoff dates, replace quadratic duplicate-ID lookup and publish
   coherent Home ranking facts. Home and Matchday projection yield between
   unpublished stages and batches without exposing mixed revisions. Fixture
   metadata is prepared once per merge. Matchday exposes individual rows to its
   lazy stack instead of eagerly building every card inside a loaded section.
10. Limit shared ImageIO decoding to two concurrent jobs. Cancelled waiters do
    not cancel another consumer's image; running decodes retain their permit.
11. Cache unchanged quality-store serialization and bound asynchronous backup
    imports, while preserving existing encryption and retention behavior.
12. Add a pull-only native playback measurement hook for physical testing. Its
    bounded scalar samples contain no URLs, headers or fixture/account details;
    it adds no production polling timer or upload.
13. Add deterministic transport, deadline, cancellation and ownership regressions.

Physical testing also exposed accessibility containers that hid player controls
and Watch Two candidates. Child controls are now reachable. A failed pane disables
its audio selector and offers Retry without blocking the working pane.

## Measurements

A repeatable 9,500-row synthetic pipeline fell from 10.527–10.624 seconds to
1.067–1.089 seconds for decoding, deduplication, discovery and Search preparation
combined. This is roughly 90% less time for that workload, not a whole-app frame-rate
claim. Repeated reads of an unchanged 250-record quality store fell from 0.841598
seconds to 0.000169 seconds over 100 reads in a Mac Debug microbenchmark.

The original iPad Search trace found three refresh-related hangs of 413, 306 and
379 ms. They motivated eliminating redundant merges, preparing fixture metadata
once and yielding Home projection work. A later 52.167-second refresh/Search
workload contained two hangs of 260 and 535 ms: sheet/layout work dominated the
first, including 27 ms of app-owned Search preparation; the second contained
native keyboard initialization and no distinctive Fotty frames. These observations
do not prove all refresh stalls or keyboard delays have been eliminated. An idle
Home trace with no hangs is only idle evidence, not a refresh benchmark.

The subsequent 46.392-second native Home/Matchday/Search trace captured batched
Search preparation outside its two reported hangs. The 433 ms Matchday transition
included 47 ms of projection and 45 ms of row measurement; the 452 ms keyboard
hang contained no distinctive Fotty frames. This prompted cooperative Matchday
projection and row-level laziness, with ordering, reminder and identity regressions.
Actual provider publication appeared separately, outside the reported hangs.

The final 46.788-second trace captured the repaired Matchday projection: 44 ms
of sampled inclusive work spread across roughly 260 ms, outside every reported
hang. Search preparation also ran outside the hangs. The only reported >250 ms
hang was 521 ms during native keyboard focus/input-view work, with no distinctive
Fotty frames. This supports the focused repair, not a promise of zero stutter;
sample weights are statistical and overlapping, not additive wall-clock timings.

## Local verification

- Current-source Catalyst unit gate: 941 total, 939 passed, two existing optional
  skips, zero failures. These are logic tests, not Mac UI acceptance for iPad.
- Signed physical iOS Release build and strict app signature verification passed.
  App and live-activity extension are both 2.0.1 (127); independent Jet iPad
  readback confirms the same installed app version.
- Final app executable SHA-256:
  `1acac6978b8ed623b0c27a44a39cab7e9f71ef219377ab0df75fd87a55060912`.
- Native source/Xcode version coherence, generated competition catalog, five
  provider identity vectors and `git diff --check` passed.

## Physical acceptance

The production-feed Home, Matchday and Search journey passed on Jet iPad. Watch
Two selection, independent source menus, audio selection, layout change and Close
passed with a 90-second soak. A real left-hand web stream remained usable while
the other provider failed and displayed Retry with audio unavailable.

The final Matchday-repaired binary passed both physical journeys again: two
tests, zero skips or failures. Normal argument-free launch and independent
installed-version readback passed. Live Home and Matchday were inspected in
Device Hub: the two-column landscape layout, section counts, badges, complete
team names and Watch/reminder controls remained intact. XCTest's exported
landscape images were partially framed, so the live mirror was used to verify
full screen geometry rather than treating those attachments as sufficient proof.
The visual-confirmation replay of the Home/Matchday/Search journey also passed
without skips or failures. Final ordinary launch remained running as PID8934.

Both selected panes had only one available source. This run does not qualify
alternate-source switching or two simultaneous decoded streams. The 98 pull
samples in the earlier soak, and 96 in the final soak, reported native measurements
unavailable; that means unknown native QoE,
not zero bandwidth. Actual sound output and native PiP/background behavior are
not newly qualified by a responsive button or a passed controls test.

## Reference implementations

The changes use applicable patterns from [Swiftfin](https://github.com/jellyfin/Swiftfin),
[Nuke](https://github.com/kean/Nuke), [Kingfisher](https://github.com/onevcat/Kingfisher),
[Get](https://github.com/kean/Get), [hls.js](https://github.com/video-dev/hls.js),
[Swift Clocks](https://github.com/pointfreeco/swift-clocks) and
[Mux AVPlayer monitoring](https://github.com/muxinc/mux-stats-sdk-avplayer).
These are references, not newly installed dependencies. Popularity does not
establish correctness, licensing suitability or a measured Fotty speedup.
The lazy-row boundary follows [Apple's SwiftUI lazy-stack guidance](https://developer.apple.com/videos/play/wwdc2026/321/).

## Cleanup and boundaries

The owned UI-test runner was uninstalled and its absence independently checked;
Fotty127 remains installed, without an app-data reset. The temporary physical
scheme and sole ~2.9 GiB gate (DerivedData, signed copies, result bundles,
screenshots and traces) were removed. Evidence summaries are retained here;
temporary artifacts can be recreated, but are not retained as raw captures.
Free disk space after cleanup:31 GiB. No unrelated artifacts or caches were removed.

This private gate is not a frozen-source shared-release qualification or
TestFlight approval.
