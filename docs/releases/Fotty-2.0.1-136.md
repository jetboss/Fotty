# Fotty Sports Hub 2.0.1 (136) — private Jet iPad qualification

10 October 2026 in Tobago; checks crossed into 11 October UTC. Private Jet iPad
gate only. Phones remain on 125 and shared TestFlight remains on 121. No Git
publication, Worker deployment, account reset, paid service or TestFlight release.
FPL feature development remains paused.

## Changes and source boundaries

Retains the five maintenance items and Home/audio ownership cleanup documented
in release 129. Subsequent private iterations repair actual footer readability,
native test measurement lifecycle, deterministic Search typing and keyboard
dismissal. Build 135 was a source-only intermediate; 136 is installed.

The owner explicitly approved the maintainer-published CS replacement and Jet
iPad validation. The old endpoint returned HTTP530 / Cloudflare1033, independently
of Fotty's Worker. The reviewed replacement is `https://nuviosports.xyz/manifest.json`.
Retain the expected add-on identity, exact team/squad/sport/kickoff match, bounded
responses and exact HTTPS origin/path admission. No permissive domain wildcard,
cross-origin redirect, P2P or generic-channel match inference was added.

CS discovery now distinguishes manifest, catalog and stream request failures,
including HTTP, transport and invalid JSON. The final per-provider report owns
the bounded local discovery receipt; an unrelated sibling cancellation cannot
hide completed CS evidence. Cancellation and deadline remain distinct. Receipts
contain safe scalar stages/codes and UUID correlation, not URLs, accounts or
fixture names. They remain in the existing 250-record / 14-day private local
store, without uploads, source-health mutation or fabricated decoded starts.

## Provenance

Original pre-build capture `backups/release-source/2.0.1-136`:

- Source SHA256 `7f1c280e9d6d976eea568e8af53d82e95599eac44e4b42037d756837c67e8270`.
- Bundle SHA256 `adcdbfab334a0adaf4ba1cb48aff42787284859abe5e6464f89ade9c1f3b56f9`.
- Frozen commit `70698d4ca469298006d5af19623842d69bd886dd`.
- Signed Release executable SHA256
  `5939b358b6df3bb9af74c52024b8391cd0fee6669c2a059398a511490285dbc5`.
- Secret/restore validation, pre-install source comparison, app/extension version
  coherence and strict signatures pass. Installed-app readback confirms 2.0.1
  (136) on Jet iPad Air 4 / iPadOS27.0.1 (24A446).

The first CS physical test exposed a harness defect: keyboard-covered reveal
swipes changed `Calgary` into `Calgaryttttttt`. The test now dismisses the native
keyboard, verifies the unchanged query and targets the exact Search result.
This is test-only; production source remained unchanged.

Separate pre-build capture `backups/release-source/2.0.1-136-ui-gate-repair`:

- Source SHA256 `7678dfdfad239fd699358c2d2ec9a69297dd909817e7778f9a5bc50a1164f8f1`.
- Bundle SHA256 `6675a75b5508109b356102bd4c29b2a4400488b06535b878b2f8b7d067a59f7e`.
- Frozen commit `82a837ac81331b089e42a7c8110ae6a93bc954ea`.
- Rebuilt test-host executable SHA256
  `a49330ad95f1359a32373971289a20330ab8d5346b81072cca5aaa4001312eb5`.

The test host is not byte-identical to the original installed executable despite
retaining build 136. Its separate source receipt includes the temporary UI-only
scheme, removed after build-for-testing. Results must identify this variant;
the original source comparison is not proof for the later test-host binary.

## Local qualification

- Fresh Catalyst: 1,085 passed, two existing opt-in skips, zero failures.
  Five offscreen FocusState warnings remain (four reminder and one component
  renderer); no audio-session warning. Fresh source tests, not the old Mac app.
- Ten reviewed non-recording component comparisons pass with unchanged goldens.
- 38 focused CS/discovery/visual tests pass; the new discovery regressions retain
  bounds, exact-source identity, cancellation and final-report ownership.
- 74 Python tooling, 31 catalog-verifier Node and nine golden-approval Node tests
  pass. Membership, version, provider/catalog vectors and diff checks pass.
- Unsigned generic iOS Release and signed UI-only Release build-for-testing pass.
  Production Release testability is not enabled merely to compile unit tests.

## Physical findings — no blanket pass

The original two-test preflight failed both tests: Home accessibility contrast
on the hero Watch label, and the CS keyboard-covered input failure above.
Neither was waived. The CS failure occurred before playback and is not a source
outage receipt.

The repaired-harness run reached the exact Calgary Flames–Anaheim Ducks result,
displayed CS1–CS5 and tapped CS1. Local discovery succeeded at 02:48:28 UTC.
CS1 audio preparation completed, but native media preparation failed on two
attempts after 1,790 ms and 1,312 ms, with `unknown` failure classification.
At 02:48:42 UTC the same watch session recorded automatic failover. No CS1
native-ready or decoded receipt qualifies this run. A later decoded receipt
belongs to a different admin/web source, not CS.

Sources reopened successfully after this interval; the failed CS1 row showed
"Try again" while Broadcast 2 was selected. The test's demand that CS1 remain
selected after a 65-second wait contradicts legitimate terminal-failure
recovery. This is not evidence of frozen controls or lost selection ownership.
Keep failed-source/failover evidence separate from same-CS decoded success.
Other real CS variants still need bounded native qualification.

The hero black/orange crop independently calculates 9.90:1 using sampled
WCAG/sRGB endpoints. That is not Apple's reported ratio or proof that its
contrast finding is false. The hero text's AX frame spans the whole button,
unlike the tighter equivalent row label. Accessibility Inspector subsequently
locates the actual hero Watch crop but reports 1.01:1 from `#F39F21` versus
`#F3A021`: two orange samples, despite visibly black text. This is an attributed
sampling discrepancy, not a clean audit. Its full Home audit also reports two
contrast, 39 unsupported Dynamic Type and one clipping warning; further
attribution is needed before calling these distinct production defects. Keep
semantic fonts and correct artwork unchanged; no exception or rebaseline.

Earlier build-134 catalog measurements passed three retained, finite app-target
iterations per surface with genuine scroll translation. Home and Matchday had
zero measured scroll hitches in those samples; Search measured 6.61, 6.41 and
14.77 ms/s with three, four and four hitches. These are dated 134 baselines,
not 136 results, FPS claims or cross-build improvement proof. Build-133 Watch
Two controls/independent source choices/90-second soak likewise are not two
decoded panels, continuous background playback or audible-output proof.

Additional 136 physical gate: nine tests, four passed, three failed, two skipped.
All three catalog measurements and the reported-finals check pass. Native PiP
fails before playback in keyboard-covered Willow Search. Home/Matchday/Search
times out in repeated 60-second XCTest Clear/refocus idle barriers. The keyboard
and query replacement harness paths are being repaired, retaining exact input,
settled-result and reachable-control assertions.

Watch Two selects two real matches, independently changes both source controls
and changes audio focus. It enters the soak, but Fotty PID10330 exits at
23:07:25 AST after about 73 seconds; runner10298 disconnects immediately after.
No completed soak, Close or two-decoded-pane proof. Diagnostics contain WebContent
`NoMemory` and repeated absent native-hook full-tree queries, but no matching
crash/jetsam termination reason. Existing device jetsam reports precede this run.
That supports checking instrumentation resource stress, not inventing a leak or
blaming a provider. A low-AX 90-second gate will avoid repeatedly traversing Web
trees for nonexistent native measurements, retaining controls/layout/Close.

Cancellation skips because the real lookup completed before cancellation;
source-switch decoding skips because the bounded counter had no net increase.
Neither skip is a pass or failure diagnosis. These results apply to the separate
136 test-host variant. Build137's header repair still needs its own physical gate.

Earlier benchmark and measurement limits remain unchanged. This candidate is
not TestFlight-qualified.

The136 measurement run's three retained Home and Matchday scroll samples each
report zero app-scoped hitches. Search reports7/6/7 hitches and19.74/22.16/27.94
ms/s hitch ratio. These are finite real-workload measurements under XCTest,
not a zero-hitch Search claim or a speed comparison against older builds.

## Watchdog follow-up

The requested researched solution is saved in
[`../operations/Fotty-Watchdog-Plan.md`](../operations/Fotty-Watchdog-Plan.md).
It separates source contracts, admitted fixture integrity, native experience and
watchdog liveness. Cloud metadata cannot clear native playback failures.
No automation, repair publisher, hosted account or unattended deployment was
activated by preparing that plan.

## Resource ownership

All heavy gates ran sequentially in one bounded owned output root without a
simulator. A task-bound `caffeinate` assertion keeps the Mac awake during this
gate without changing security/lock settings. Cleanup must remove only this
gate's runner and temporary outputs after the results are summarized, preserving
the local frozen recovery bundles and unrelated owner artifacts.
