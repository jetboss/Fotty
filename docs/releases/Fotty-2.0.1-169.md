# Fotty 2.0.1 (169): one additional NHL source qualified on Jet

23 October 2026. Private Jet iPad only. FPL, multi-stream, phones, shared
TestFlight, cloud deployment, Git publication and spending remain out of scope.

## Delivered scope and limits

- Add optional CNCVerse/LivXow sources as a separately attributed LS1–LS6 family
  within existing exact match source lists, not a new fixture authority or a
  separate setup workflow. LS is OFF by default and privately ON on Jet for the
  requested source testing. Existing CS/Score808/StreamEx choices stay unchanged;
  AS/Plavio remains OFF.
- Current qualified contract is NHL/hockey, explicit UTC metadata, exact two
  teams/squad/date and reviewed host7 HTTPS443 HLS delivery/public headers. Keep
  conflicting/malformed sibling vetoes, bounded requests/bytes/caches, opt-in
  rechecks, transport/DNS/TLS/redirect/header restrictions and redacted source keys.
  No arbitrary add-on installation, opaque-ID decoding or channel-based fixture
  inference. No extraordinary port or source-specific relay trust exception.
- This is a genuinely additional delivery adapter, not renamed CS. Independent
  upstream resilience, rights and long-term availability are not established.
  One sampled NHL fixture is not every NHL match or additional football/cricket
  coverage. The researched candidates that did not qualify are in the audit.

## Confirmed fixes found during qualification

- AVPlayer's two-byte playlist Range probe was forwarded upstream and the relay
  attempted to rewrite that partial response as a full manifest. A bounded probe
  reproduced HTTP206/two bytes versus fullGET200/721 bytes. Suppress Range and
  representation/cache preconditions only for known m3u8 requests. Require
  full200/noContentRange before rewriting/HEAD; rewritten GET owns its length and
  omits stale origin validators. Keep ordinary segment ranges. Partial/conditional
  MIME-only manifests fail closed without retries or status laundering.
- A reviewed LS ordinary-single session gets one immutable30s native startup
  allowance after full contract revalidation. Default20s, pair/handoff, Pause,
  cancellation, ownership, fatal and hard-deadline behavior are unchanged. No
  generic buffering/stall tolerance or recovery policy is weakened.
- The observed source label contains an emoji ZWJ sequence. Permit only that
  exact reviewed sequence while still rejecting arbitrary format/control text.

## Failed intermediate candidates remain rejected

The CNC NBA host4 feed briefly decoded, then failed the longer90s hold. Its
normal-app attempt also stalled and failed over. Those failures are retained,
not overwritten by the early20s canary pass. Basketball/NBA and host4 are not
admitted by this final hockey contract.

An offline synthetic one-MiB physical test passed exact byte equality over direct
data, direct AsyncBytes and the actual guarded relay:3.308ms/65.296ms/81.763ms
respectively, approximately12.23MiB/s for the relay. This excludes only a basic
capacity shortage in that controlled setup; it does not prove provider fault or
exclude all real-network/player timing defects. A first diagnostic used a
deliberately blocked invalid-domain fixture; correct only the intercepted test
host, not production transport policy.

Plavio's earlier zero-frame native failure remains in release168. Generic-channel,
authentication-placeholder, challenge-wrapper and self-host-only alternatives
were not enabled to inflate the source count.

## Verification

- Fresh NHL-focused Catalyst gate:287 total,285 passed,two intentional
  physical-only skips,zero failures. Source client/matcher/integration, optional
  lookup/discovery, registry/settings, relay, local quality and native startup
  evidence suites are covered. Four existing Watch Two tests are excluded; no
  simulator, FPL or multi-stream testing is performed.
-32 membership-tool tests pass. Explicit membership188 app/62 unit/5 UI/5
  extension; project.yml and four Xcode configurations agree on2.0.1(169).
  Existing test-host Sendable warnings remain. A version script invocation without
  its required paths fails; the correctly parameterized verification passes.
- Final NHL physical canary:one passed,zero failed/skipped;102.412s overall,
  877 real1280x720 pixel buffers,91.966s decoded progress,89.933s advancing
  progress across the90s hold. Visible layer ready; retained relay ring31
  completed/zero failed/one in flight. Initial HTTP/player-clock success alone
  does not qualify this test. Test display/player/relay resources are retired.
- Final normal signed Release169 build passes with empty build diagnostic log;
  app+extension169, strict deep signature, frozen source comparisons before and
  after install, exact Jet installation/readback/launch pass.
- Normal Home lists the existing Chicago Blackhawks–Montreal Canadiens fixture.
  Sources has six existing broadcasts plus seventh LS1. Selecting LS1 starts
  native decoded progress in3346ms; its redacted key equals the newly sampled
  host7 delivery, not the prior NBA key or another provider's fallback.
- Real programme is visible: Canadiens versus Blackhawks on Chicago Sports
  Network, first-period8:14/CAN0–CHI1, then intermission CAN1–CHI1. Provider
  commercials/intermission are programme content, not a new click-through UI.
- Native fullscreen/return, deliberate Pause and resumed inline video are
  observed. LS1 remains selected after those controls. The single normal attempt
  spans264.984s including deliberate pauses, with one startup, no playback-failure
  event or automatic failover. Two finite waits of9ms and2052ms are recorded;
  do not call it stall-free or an uninterrupted4.4-minute soak.
- Stop closes the attempt and returns Home; no test stream remains. Keyboard
  capture stays OFF.45 protected FPL/multi-stream file hashes and four private
  FPL/manager/coach preference values match baseline. Existing source preferences
  are unchanged; only the new private LS opt-in is ON.

PiP/background/lock-unlock, audible output, every NHL fixture and long-duration
production reliability are not newly qualified. No inherited broad pass claim.

## Final source receipt

1136 frozen inputs compare before/after installation, before documentation-only
closeout. The history-free capture leaves real Git refs/index/remotes unchanged.
No archive/IPA or upload was produced.

- Label: `2.0.1-169-final`.
- Temporary snapshot commit: `95ed6dbec5f4ea76b167cbaa0507be539b174cb9`.
- Source SHA256: `1d6039969c2615b75c3160ec6bcb9b780d8a1261c3c155bd84164d1310175459`.
- Bundle SHA256: `ddd85857ce0be161b94c9a66c8975b29d579d2d6d87f86d7993f05b05656cf70`.
- Signed executable SHA256: `f203fdf815b33b70328a9e7cd886407c68800b8158338e02cc564520341a6d09`.

The owned bounded gate, DerivedData, result bundles, private samples/preferences
and temporary snapshot are deleted after verification. Only this task's awake
helper is stopped. Preserve all pre-existing user caches/artifacts. No simulator
or parallel heavy build is used; disk is checked before and after the gate.
