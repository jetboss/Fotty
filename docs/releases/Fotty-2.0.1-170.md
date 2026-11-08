# Fotty 2.0.1 (170): AS live-schema repair, Jet decoder pass

24 October 2026. Private Jet iPad only. FPL, multi-stream, phones, cloud,
Git publication, spending and shared TestFlight remain unchanged.

## Focused repair

AS/Plavio changed its current football entry to an undated four-line LIVE
description and a literal public ID without the older football prefix. The
existing adapter rejected that row even though its match delivery was playable.

Keep the original dated parser unchanged. For only the reviewed LIVE shape,
join its literal public ID to a fresh, fixed HTTPS publisher metadata route.
Require explicit sport, full UTC date, both participants and title/squad agreement
under the existing shared matcher. Preserve malformed/conflicting duplicate
vetoes, request/body/row/cancellation bounds and all existing delivery/relay
TLS, public-IP, redirect and header restrictions. Never infer a date from LIVE,
current time or a slug. Default AS remains OFF.

## Verification actually completed

- Twelve new regression methods. Focused Catalyst gate: 49 tests, 48 passed,
  one intentional physical-only skip, zero failures. No simulator.
- Jet's opt-in AS helper uses the real adapter and guarded relay, pinned to
  Aston Villa–Manchester City, 24 October 11:30 UTC. Fresh published schedule/
  status and explicit upstream fixture metadata corroborate that identity.
- Physical test: one passed, zero failed/skipped; XCTest 95.344s. Decoder
  evidence: 878 actual 1280×720 pixel buffers, 92.080s decoded progression,
  including 90.000s during the hold against an 80s minimum. Visible surface and
  layer ready, player rate 1. Retained relay ring: 32 completed, zero failed,
  zero in flight/cancelled, four evicted. This is not a count of all requests.
- Contemporaneous native image shows TNT's AVL 1–0 MCI at 32:13, not merely
  an advancing player clock or a generic channel. Canary audio was muted.
- Normal signed Release170, without the opt-in canary flag, builds with an empty
  diagnostic log; app and live-activity/widget extension both170, strict deep
  signature passes. Exact Jet install, installed-version readback and launch pass.
- 45 protected FPL/multi-stream file hashes and all four private FPL/manager/
  coach preference values match baseline. Every existing source preference is
  preserved, including AS OFF and Jet's prior LS ON.

## Open gates — not an end-to-end source qualification

The normal AS picker, selection, Pause/Resume, fullscreen and PiP gate remains
unverified. Device Hub showed current Home and an unlocked device, but mirrored
taps only moved/hovered and did not activate Settings. A screen-sharing reconnect
did not resolve it. This observation does not establish a Fotty UI hang or its
cause. Keyboard capture was returned OFF, no normal AS attempt was started,
and no source setting was injected to manufacture acceptance. The device is
left on normal Home, not the test host. AS stays OFF until that gate passes.

Additional cricket remains pending: current reviewed descriptors were either
incompatible, unavailable, differently dated or lacked programme corroboration.
No access, authentication, DRM or transport exception was introduced. One sampled
football decoder pass is not whole-league reliability, independent upstream
supply or cricket coverage. See the dated new-sports-sources audit.

## Frozen source receipt and cleanup

1137 inputs compare before and after the normal installation, before this
documentation-only closeout. Real Git refs/index/remotes are unchanged.

- Label: `2.0.1-170-private-AS`.
- Temporary snapshot commit: `7de8ceaca07cfc8926d6281ab242ebc2449918d5`.
- Source SHA256: `2aa0df9ea5474597ac348cc16212c5a5792252a1cc807961d219e91a465a5e8f`.
- Bundle SHA256: `5933b8b16741426874d13650b200fd0b66383965b520c45856ee01d5ee29f769`.
- Signed executable SHA256: `4b0fdd490557b3ef3184aca8372b73ad852af43dc654e6c6668e80a7f39adecc`.

The bounded owned gate contains the temporary source snapshot, media samples,
preferences, DerivedData and results; remove it after preserving this redacted
receipt. Stop only this task's temporary awake helper and check free disk.
Pre-existing artifacts, caches and awake processes are not cleanup targets.
