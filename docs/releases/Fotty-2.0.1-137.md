# Fotty 2.0.1 (137) — private Jet iPad gate

Prepared 10 October 2026 in Tobago; late checks cross into 11 October UTC.
Installed only on the approved Jet iPad. No phone installation, TestFlight,
Git publication, Worker deployment, source activation or user-data reset.
Owner phones retain125; shared TestFlight retains121.

## Production change

The CS replacement's reviewed DaddyLive adapter advertises public request
headers needed by its native media delivery. Fotty previously discarded those
delivery hints. Build137 carries admitted `Referer`, `Origin` and `User-Agent`
through `PlaybackSession.requiredHeaders` to the existing guarded local proxy.
This corrects an adapter contract gap; it does not establish the precise cause
of build136's two `native_preparing` failures or guarantee an upstream stream.

Admission is fail-closed: at most three canonical, unique, bounded printable
ASCII request headers; no credentials, cookies, arbitrary request headers or
response-header instructions. Referer/Origin must match exactly one advertised
manifest query value, pass existing public HTTPS constraints and agree on
origin. Origin must be a root origin. Required headers cannot silently disappear
into a web delivery route. No delivery-origin/path, TLS, trust, source-identity
or stream-label expansion. Malformed advertised contracts cannot become absent
headers. Existing proxy ownership and attempt fences stay unchanged.

Reviewed upstream contract:
[maintainer's DaddyLive adapter at3826108](https://github.com/rajhodedara/live-sport-plugin/blob/3826108b881f1ca25f40f583f9f5e3aa8d26d37d/src/providers/DaddyLiveProvider.js).
The bounded upstream check read metadata and one small playlist, not media
segments. Eligible options and an HTTP200 playlist are not native decode proof.

## Exact build receipt

The first reachability source was frozen before its signed UI-only Release build:

- Receipt: `backups/release-source/2.0.1-137-ui-reachability/receipt.json`.
- Recovery commit: `2cb9b1283aa27055dccb85e6585164de5a05c2d5`.
- Source SHA-256: `5a6038369d79bf2c08051134ed6fde753994e1a1f02f467b3702036c9f2f4e76`.
- Bundle SHA-256: `9eb6e8cc34a3994aa6ffcbc616d7a45590ca959312864ff88608363c0e849017`.
- Signed app executable SHA-256: `fc30fda1f1e03edbd601e0f2a716cef665045452e18b59f499c7df29d1ba946d`.
- Verified1054 source files. Temporary UI-only scheme created after capture and
  removed before the passing working-source comparison; no Release testability
  change. Exact test selection/environment is recorded in the generated run.
- App and Live Activity extension versions137, strict deep signature validation,
  installation and independent installed-app readback pass.

The final passive-canary harness has a distinct pre-build receipt and executable:

- Receipt: `backups/release-source/2.0.1-137-passive-canary-final/receipt.json`.
- Recovery commit: `1fe93d3da0329f843b209b05d648a7d9e6fce6f4`.
- Source SHA-256: `97ad99c17745eebf71f840c91a82503064f25bfd441e6302e8ccb978cfc99274`.
- Bundle SHA-256: `b05ffb2f6d937594ed38accd319c1918774ce60da08973d726bb907ef17fc226`.
- Signed app executable SHA-256: `2660e8ba16b45f673ce7a0025875dc8ffe6993729e69bbbb6c46631a50c6dfd5`.
- Verified1055 files, signed UI-only Release build, strict deep signature,
  pre-install source comparison and independent installed137 readback pass.
  This receipt owns the final installed binary; preceding physical results
  remain attached to their earlier binary, not silently transferred.

The earlier `2.0.1-137` and `2.0.1-137-passive-canary` captures predate subsequent
test-only repairs and are recovery captures, not provenance for the final
installed binary. Original136 and its separate keyboard-harness binary retain
distinct evidence in `Fotty-2.0.1-136.md`. Evidence documentation is updated after
the frozen build; it is not a claim that later whole-tree comparisons stay equal.

## Local verification

Freshly built Catalyst logic:1095 total,1093 passed, two existing optional skips,
zero failures. All eight new public-header regressions pass, including malformed
contracts, unsafe provenance, credentials, oversized/control/Unicode values,
deduplication and unchanged no-hint routes. Five offscreen FocusState warnings
remain in tests; no audio warning. No simulator or old installed Mac app used.

Unsigned generic iOS Release and signed UI-only Release build-for-testing pass.
Membership remains172 app/44 unit/4 UI/3 extension sources. Version coherence,
generated competition catalog, five provider identity vectors and diff checks
pass. Build136's ten reviewed component goldens remain dated unchanged evidence,
not a new137 native visual/accessibility qualification.

## Physical qualification

The exact Calgary–Anaheim CS gate passes: one test, no failures/skips or runtime
warnings. CS1 explicitly failed and a distinct fallback remained selected; that
is not CS1 recovery. CS2 then remained selected with a ready native layer and
same-item media-time progress. Sources reopened, and Close returned Home.
The retained gate attachment records the family distinction. This qualifies
brief CS2 progress, not all variants, CS1's required-header transport, sound or
continuous background playback. The existing private local quality ring records
CS2 decoding at03:22:48 UTC, then an `unknown` failure at the `decoded` stage
at03:23:02, followed by a same-family retry decoding at03:23:03. Thus the passed
brief test is not a sustained-playback pass. No URL, header or owner ID was
uploaded; these redacted classifications do not identify an exact upstream cause.

The initial remaining137 run reports zero passes, two failures and one skip.
Home/Matchday navigation reaches Search, where the Select All automation path
retains `cr` instead of the committed `cricket`; all seven key events are logged.
This is real input loss in that path, not a missing-focus or idle-timeout claim.
Its cause and ordinary-use impact are not isolated. The native PiP test skips
because its default/alternate real sources do not qualify native progress;
that is not PiP acceptance or a proven PiP defect.

Watch Two independently changes both sources and audio focus, but runner10486
disconnects at23:27:45.440 AST and reports signal kill. The last successful
Fotty10506 snapshot is23:27:41.011; its launch-tracker termination follows the
runner disconnect. Unlike136, this log has no preceding app Not Running event.
Thus137 confirms a runner failure, not an independently proven Fotty crash.
Failure occurs about49 seconds into the soak before layout/Close. Native hooks
are checked once; the low-AX repair executes correctly. WebContent helper/DNS
NoMemory evidence remains, not a proven RAM/jetsam explanation. No matching
current device crash report was available. The macOS-password-blocked optional
diagnostic collector was canceled, without password entry/security changes.

A final test-only editing/passive-canary gate uses exact-element keyboard
typing and retains the exact query/result assertions. Its Home/Matchday/Search
journey passes57.495 seconds with complete `football`, `cricket` and `zz`
queries. This qualifies completed queries, not per-prefix stress or isolated
latency. A CS-configured PiP setup fails68.706 seconds before starting PiP:
the proven native item token changes while the same CS row remains selected.
The strict gate prevents a replacement item from becoming CS PiP proof; no
background PiP attempt is qualified by that failure. The local ring resolves
this interval: CS2 decodes03:40:56 UTC, records an `unknown` decoded-stage
failure03:41:07, starts a new attempt that same second and decodes03:41:09.
This is a real retry, not grounds to change the measurement hook. The exact
AVFoundation/upstream cause remains unavailable; selected-row continuity alone
does not mean the same native item survived.

Final result: three tests, one pass, two failures, zero skips/runtime warnings.
The separate120-second passive Watch Two canary fails before completing its
interval, layout transition or Close. Last deliberate UI query finishes
23:42:49.733 AST; Fotty10599 logs Web startup-timeout/failover through
23:44:02.704. Runner10575's launch session expires23:44:05.369 and connection
ends.374, with Fotty's launch-tracker termination only afterward. There is no
preceding Fotty Not Running notification or explicit application exception.
This is a runner/session failure after about76 passive seconds, not a proven
Fotty crash. No current NoMemory entry or matching current crash/Jetsam report
explains it; fresh crash listing contains only earlier19:42/20:24 Jetsam files.
Both Web attempts retain document-loaded startup-timeout/retry/failover evidence,
not two decoded panes. No deliberate intermediate AX/state/screenshot queries
occur during the passive interval. Repeated polling therefore cannot be the
sole explanation for these failures. No speculative playback/hook repair is made.

Preserve the initial failure/skip receipts; an additional low-interference
canary cannot retroactively turn the polling gate into a pass. Device Hub's live mirror
renders normal Home, but coordinate clicks did not operate its device surface;
that observation does not qualify a normal-build interaction or two-pane soak.
Tests use real production feeds and muted physical-test mode without fixtures,
enabling sources, resetting persistence or uploading diagnostics. Native time
progress is distinct from audible playback and continuous background frames.

Test-only repairs retain exact query/result/source assertions: dismiss the
native iPad keyboard before revealing a covered Watch; replace whole Search
queries with native Select All rather than repeated Clear/refocus idle waits;
distinguish a failed CS row with a selected fallback from actual CS progress.
The 90-second Watch Two gate samples controls and only initially available
native scalar hooks, retiring a hook when unavailable rather than repeatedly
traversing absent Web trees. It retains independent source/audio controls,
layout transition and Close. This addresses measurement interference, not a
proven explanation for build136's app/runner exit.

## Operational follow-up

The researched [watchdog plan](../operations/Fotty-Watchdog-Plan.md) separates
source contracts, accepted fixtures, native experience and monitor liveness.
Independent review found no blocking planning gaps. It is a proposal, not
activated monitoring, unattended publishing or paid agent execution.

The gate reuses one owned temporary output directory and task-bound keep-awake.
Owned runner, build products, results, private preference copies and audit
screenshots are removed after verification; retained source receipts are
deliberate recovery artifacts. The optional password-blocked diagnostic
collector is canceled without password entry or security changes.
