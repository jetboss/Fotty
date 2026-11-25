# Fotty2.5 implementation and qualification

24 October2026. This is local implementation, not a distributed2.5 release.
The owner iPhone and Jet iPad remain on their existing signed2.0.1(175) for
25October feedback. The working version is deliberately not relabeled, installed
or uploaded. FPL and multi-stream are excluded. All five workstreams follow the
[approved roadmap](Fotty-Stremio-CS-Usability-Review-2026-10-23.md).

## Implemented in order

1. **Curated source engine.** `CuratedStreamSourceCatalog` owns seven reviewed
   registration identities, manifest/provider binding, defaults, opaque labels,
   category/optional-fixture gates and typed dispatch. Registry, matching,
   resolver and five optional adapters consume it. Saved choices and existing
   six-option limits remain intact. A bundled ID cannot borrow another provider
   code. Adapter-specific identity, conflict, TLS, public-address, redirect,
   required-header and delivery restrictions are unchanged. No generic add-on
   installer, new source enablement or new player dependency.
2. **Single-player journey.** An opt-in incremental observer publishes admitted,
   header-aware deduplicated choices from the existing bounded collector. Existing
   aggregate callers retain their API. Home/Matchday single Watch uses one
   scene-owned task: immediate feedback, first usable choices, append-only later
   alternatives, exact owner/generation cancellation and current local catalog/
   status revalidation. No duplicate catalog preflight is added ahead of independent
   lanes. Opening Sources, receiving alternatives, minimizing and ordinary renders
   do not change the active source/index, player/item, attempt or Pause. Selecting
   another source remains explicit replacement. The picker separates checking,
   completed-empty and available choices, and offers a native reviewed-family
   filter only when useful; it never exposes remote names/URLs as group labels.
3. **Browsing/planning.** Basic schedule/broadcast context expands within the
   Home/Search/Matchday row; full existing details remains reachable. Watch is
   not diverted through an extra screen. Visible native More actions expose
   existing Save/Remove/Details where a context callback exists. Interests,
   query, scrolling, badge identity, sport artwork and Save/Remind ownership stay
   unchanged. No channel-to-fixture or EPG inference.
4. **Native consistency.** Existing settings are grouped by task and use
   consistent Playback sources wording. Supported registrations are not labeled
   as proven working broadcasts. Existing themes, readable/accessibility reflow,
  44pt actions and video-first/native controls are retained. See the
   [screen contracts and visual ledger](Fotty-2.5-Native-Experience.md).
5. **Measured work and responsiveness.** Search preparation is catalog-owned,
   not cancelled by each nonempty query edit; only latest-query results publish.
   Home uses the same two-pass dedup accumulator in cancellable batches of at
   most32 rows, preserving atomic publication. Other dedup callers remain
   synchronous. Failed badge URLs receive a two-second, memory-only, monotonic,
  256-entry retry cooldown; warm authoritative cache hits and changed URLs win
   immediately, and cancelled work cannot poison the retry state.

## Evidence and limits

REA6.4.0's retained actual Stremio Apple2.0.7 package records remain the shipped
artifact reference: [canonical evidence pack](../testing/rea/stremio-2.0.7-2026-10-24/README.md).
The main-image evidence `ev_82b1e1702c5c593059290ae47f9aee553dcca4ebcf06125c6371dfa3674fd330`
establishes AVKit/AVFoundation/KSPlayer dependencies, not a selected decoder,
startup speed, buffering policy or2.1 native implementation. Its public Web source
is a separate reference for ready-provider presentation. Fotty's implementation
is original native code; no proprietary assets or GPL player code is copied.
No unconfigured decompiler/extra engine was installed merely to claim REA use.

### Local baseline — fresh Debug Catalyst host

MacBook Air/macOS27.0.1, Xcode27.0/27A266a, arm64, one job. These synthetic
measurements are not physical iPad scrolling, network speed or decoded video.

| Workload | Baseline observation |
| --- | --- |
|250-row cold Search index,3 samples|15.804–19.487ms;250 classifications/sample|
|1000-row cold Search index,3 samples|62.882–64.499ms;1000 classifications/sample|
|12 warm queries over1000 rows,3 samples|23.129–23.908ms total/sample|
|1000 input /250 unique duplicate-heavy rows,3 samples|52.390–54.655ms synchronous dedup|
|4000 input /1000 unique duplicate-heavy rows,3 samples|205.751–218.620ms synchronous dedup; discovery48.871–51.093ms|
|32 recreated badge consumers with failing preferred URL/cached fallback|32 preferred requests;0 fallback requests;32 accepted fallback images|

The baseline executed390 tests:387 passed,2 optional physical canaries skipped,
one obsolete source-location assertion failed after feedback ownership moved to
the scene coordinator. That assertion now checks the new owner and both callers;
it was not removed. Initial compilation also caught and corrected a catalog
actor-isolation annotation and a missing test fixture argument.

### Final local checks

- Fresh Catalyst build-for-testing and final execution both exit0: **579 passed,
  0 failed,3 skipped** out of582 selected checks. The skips are two FS physical
  decoding canaries and one AS guarded-relay physical decoding canary; none was
  run against a device or counted as a playback pass.
- Generic unsigned iOS **Release build exits0**, version2.0.1(175), no provisioning,
  signing, archive, install or upload. It is a compile check, not the signed175
  currently installed on either device.
- Native membership passes (191 app/65 unit/5 UI/5 extension source entries);
  source/Xcode versions agree; whitespace checks pass. All51 FPL/multi-stream
  source/test hashes are unchanged. The296-file listed-tree digest is identical
  before/after Release compilation; see the receipt's explicit coverage limits.
- [Redacted machine-readable receipt](../testing/Fotty-2.5-local-gate-2026-10-24.json)
  retains counts and raw scalar measurements, not result bundles, diagnostics,
  signing material, media, private values or device identifiers.
- Removed the owned1.5GiB build/result/log gate and stopped its keep-awake helper;
  about10GiB free afterward. Generated outputs are rebuildable; no user cache or
  pre-existing artifact was removed.

| Focused repair | Final controlled observation |
| --- | --- |
|Search typing,96 rows/two edits|Old query-owned pattern performs128 classifications/3 attempts; catalog-owned preparation96/1; identical final results. This is avoided-work evidence, not a25% app-speed claim.|
|Home4000/1000 duplicate workload,3 samples|157 cooperative checkpoints/sample; observed maximum work between checkpoints1.990–2.013ms; total211.559–215.140ms. Sync output/metadata/source order matches exactly.|
|32 recreated badge consumers|1 failed preferred request,0 fallback requests,32 identical accepted cached fallbacks. Expiry, cancellation, changed URL, warm authoritative cache and256-entry bounds are tested.|

Home's benchmark injects yield-only checkpoints to isolate batching; production
retains the existing one-millisecond suspension. Those elapsed values are not
production wall time or proof of rendered input responsiveness. Total CPU work
was not claimed eliminated. The synchronous comparison remains204.969–205.433ms
in the final run. Search's1000-row index still costs58.161–58.366ms in this run;
the repair prevents discarded/repeated work rather than attributing normal
warm-run timing differences to a faster normalization algorithm. Physical traces
and any remaining synchronous discovery-stage cost stay open below.

## Deliberately open gates

- Real iPhone/iPad visual acceptance: dark/light, accessibility text, narrow/wide
  windows, keyboard, inline expansion and anchored menus.
- Real single-player controls/fullscreen/PiP and a decoding hold for this new
  source snapshot; unit ownership checks do not establish on-device playback.
- Pending CS/FS/SV and AS-cricket/PL/UCL programme/decoded qualification remains
  in the source audit. This refactor does not turn an admitted descriptor into
  a working-stream claim or enable a pending source.
- Physical Release responsiveness, thermal/memory and comparable tap/source/
  decoded/recovery intervals. Cooperative test slices are not hitch statistics.
- A separately approved signed candidate, device install and later significant
  TestFlight batch. No publication or release is authorized here.

The three existing bounded source-check follow-ups now explicitly honor the
175 freeze: metadata-only, no device/app/settings interactions until the owner
ends the hold. Their original schedules/expiry remain unchanged. They must not
replace175 automatically or extend campaigns to make a missing pass disappear.
