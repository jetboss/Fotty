# Fotty PiP background-control correction

Date: 2026-09-06

## Reproduction

The owner reproduced the issue on Jelani's iPhone using internal TestFlight
2.0.0 (75). A native cricket stream entered the system Picture in Picture
window, but the video was paused. The PiP Play button did not resume it until
Fotty returned to the foreground.

## Root cause

The original diagnosis covered Fotty's native `AVPlayerLayer` path, but the
reproduced cricket session did not use that path. A physical-device AVKit and
WebKit trace showed that the provider's HTML video entered WebKit-owned PiP
successfully and was playing. When the Fotty scene moved to the background,
`LivePlayerView` passed `isSuspended = true` to the embed and Fotty's injected
JavaScript paused every media element. AVKit then reported the WebKit player as
paused while its PiP window remained visible. The PiP Play control could not
override Fotty's application-level suspension until the app returned to the
foreground.

A second race could replace the owning `WKWebView` after a native manifest
candidate was discovered. Dismantling that web view pauses its media and can
invalidate WebKit-owned PiP, so native handoff must not begin or complete while
the app is backgrounded or WebKit PiP is active.

## Correction

- The injected WebKit monitor now reports standard and prefixed PiP presentation
  events for the confirmed broadcast video and relays them from an owning child
  frame even while the top document is becoming hidden.
- `LivePlayerViewModel` tracks WebKit PiP separately from native PiP. Active web
  PiP cancels background suspension and preserves the same web view, source and
  stream attempt.
- Ordinary web playback still suspends in the background, but only after a
  750-millisecond grace window in which WebKit's PiP event can win the scene
  transition race.
- Native handoff is cancelled and rejected while WebKit PiP is active or the app
  is backgrounded, preventing SwiftUI from dismantling the PiP owner.
- Closing WebKit PiP while Fotty remains backgrounded returns to the bounded
  suspension path; foregrounding revokes the suspension and resumes the same
  attempt when appropriate.

This keeps Fotty's required playback audio/background configuration while
respecting the actual owner: AVKit for native playback and WebKit's
`AVPlayerViewController` for provider HTML video.

## Verification

- Focused regressions pass for WebKit PiP event ownership, document scoping,
  duplicate-event suppression, the background/PiP race, ordinary background
  suspension and native-handoff exclusion.
- The complete simulator-free unit suite and generic iOS Release compile pass.
- Physical-device tracing of rejected build 77 identified the WebKit suspension
  call immediately preceding AVKit's playing-to-paused transition.
- Private optimized build 78 passed strict signature verification and installed
  in place only on Jelani's iPhone. The owner subsequently repeated the failing
  provider PiP path and confirmed the correction works. TestFlight remains 75.
- All temporary DerivedData and build logs were removed; no artifact was
  uploaded or retained. The Mac retained approximately 47 GiB free.

## Physical acceptance — passed

The owner tested build 78 on Jelani's iPhone using the provider-backed PiP path
that failed in builds 76 and 77 and confirmed it is fixed. Build 78 is therefore
the accepted private PiP baseline. This acceptance is scoped to the reproduced
WebKit-owned PiP failure; it does not upload or promote the build to TestFlight.
