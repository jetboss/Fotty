# Fotty 2.0.0 (78) — private WebKit PiP lifecycle correction

Date: 2026-09-06. Status: **physically accepted on Jelani's iPhone; not uploaded
to TestFlight**.

## Outcome

Physical tracing proved that the failing cricket stream used WebKit-owned PiP,
not Fotty's native `AVPlayerLayer` PiP. Fotty was explicitly suspending the HTML
video when its scene entered the background, leaving a visible but paused PiP
window. Build 78 tracks the confirmed web video's PiP presentation state,
allows that event to win the scene-transition race, and keeps the owning web
player alive.

Native handoff is also blocked while WebKit PiP owns playback or the app is in
the background, preventing an asynchronous player swap from dismantling the
active PiP web view. Normal non-PiP web playback continues to pause safely after
a short background grace period.

## Verification and installation

- JavaScript execution tests cover standard and WebKit PiP presentation events.
- Bridge tests cover owning-document scope, unrelated-frame rejection and
  duplicate state suppression.
- Lifecycle tests cover PiP winning the background race, normal background
  suspension/foreground recovery and native-handoff exclusion.
- The complete simulator-free unit suite and generic iOS Release compile passed.
- A signed optimized Release app passed strict nested signature verification and
  installed in place only on Jelani's iPhone. CoreDevice confirms version 2.0.0
  and build 78.
- The phone was locked when remote launch was attempted; installation still
  succeeded and the owner subsequently launched and tested the build.
- TestFlight remains build 75. No simulator, upload, other-device installation,
  uninstall or data-container reset occurred.
- The cleanup trap removed all owned build products. Disk space remained about
  47 GiB free.

## Physical acceptance — passed

The owner repeated the previously failing provider-backed PiP path on build 78
and confirmed that it is fixed. This physically accepts the WebKit-owned PiP
background/Play correction on Jelani's iPhone. Builds 76 and 77 remain rejected;
build 78 is the accepted private baseline. Wider TestFlight promotion remains a
separate decision.
