# Fotty 2.0.0 (38) — iPad layout and Settings follow-up

Status: installed on the owner's physical iPad Air 4 only; not uploaded.
TestFlight remains 2.0.0 (35). The owner's iPad-only diagnostic exception applies.

## Changes

- All sport tiles share their measured width and tallest height, including the
  final partial row. Titles reserve two lines. iPad shows every listed sport in
  width-aware rows without More sports, including compact Split View. Compact
  phones keep their bounded selector and selected-overflow continuity.
- Settings → Appearance is a normal labelled destination with Dark (default),
  Light and System choices. Engineering is removed from normal Settings even
  in Debug; Report a problem remains.
- Static NBA/MLB artwork fallbacks cover current clubs, and sparse persisted
  badge caches no longer erase bundled fallbacks. No new runtime catalog API.
- Inherits builds 36–37's playback and adaptive-theme work without another
  provider-control or recovery change in this layout pass.

## Qualification

- 155 unit tests passed, one optional HLS soak skipped, zero runtime warnings.
  Geometry checks include multirow tallest-height measurement, phone/iPad/Split
  View visibility, scaled column capacity and empty/unspecified proposals.
- Light/dark Home components and actual Appearance choice content were rendered
  and inspected. A new nonblank-snapshot assertion caught UIKit-backed scrolling
  containers rendering only their background in offscreen Catalyst snapshots.
  The real choice component is now separately renderable; the empty captures
  are not visual evidence. Catalyst size-category previews do not certify the
  physical iPad's larger text, VoiceOver or preference-switch interaction.
- Normal Release, ReviewSafeRelease and signed Debug generic-iOS builds pass.
  App and extension both report 2.0.0 (38); strict deep signature verification
  passed. CoreDevice independently reports the installed iPad app as 38.
- Executable SHA-256 at install:
  `03565942d81f41dab77176a14cfe4c474a154a07dec2fc044217abac40f17266`.
- Physical portrait Home shows eight equal-width columns with all remaining
  sports in a second equal-height row, no More sports, and actual Yankees/Astros
  badges. A capture requested after a Settings launch still showed Home, so it
  does NOT verify Settings navigation or preference interaction. The masthead
  appears under the status area in that capture; recheck its scroll/safe-area
  state separately rather than declaring the entire Home layout certified.
- Returned to an ordinary argument-free launch; the normal app survived a
  20-second process hold. No device UI-test helper was installed.
- The cleanup trap removed the single 1.3 GB owned build/test/capture directory
  after verification. Its absence was checked; disk returned to 40 GiB free.
  Only the normal installed app and small source/test/audit records remain.

No simulator, device UI-test helper, iPhone install, TestFlight upload, tester
change, paid API or Git publication. Same-control centre/lower-left pause and
resume remains a separate physical acceptance item.

## New owner report — action/availability mismatch, not changed in 38

The owner reported that Open broadcast starts a lookup and then reports no
streams. Source inspection confirms that Home's `canWatch`/`isPlaybackCandidate`
checks only for a supported catalog provider descriptor. Watch versus Open
broadcast is determined by event timing, not resolved stream availability; both
route to `watchEvent`. Actual resolution happens after the tap, and an empty or
failed result then shows the error. This explains the misleading affordance, not
the exact provider-side reason for that individual failed event.

The owner prefers an inline Starts in countdown, becoming tappable with a play
icon about one or two minutes before scheduled start, and questions the value
of any extra details screen. Recommended next decision: a passive countdown until
two minutes before start, then an explicit attempt; inline Not ready / Retry on
an empty lookup. Keep useful Match Center information separate, and retain
continuous-channel access without a fabricated countdown.
Do not label a catalog descriptor as verified playback, probe all feeds in the
background, or block live manual attempts solely on historical provider health.
The revised countdown interaction remains under discussion. No action/routing
behavior was changed in 38 and no build 39 was produced.
