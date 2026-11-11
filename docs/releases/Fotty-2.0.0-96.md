# Fotty 2.0.0 (96) — private native-control ownership correction

2026-09-13. Status: **rejected after physical retry; superseded by build 97**.
This build is not uploaded to TestFlight.

## Correction

CS exposes same-origin HLS through Fotty's native `AVPlayerLayer` path. That
UIKit surface can win physical-device hit-testing over visibly composited
SwiftUI controls. Build 95 added a reliable surface tap but left the video view
interactive after controls appeared, causing Close, Play/Pause, Sources, PiP and
fill controls to ignore touches.

Build 96 makes ownership explicit. The native video surface captures the reveal
tap only while controls are hidden. It disables its own interaction whenever
controls, loading, or error UI is visible, allowing those layers to own touches;
it is re-enabled when controls hide. The misleading automatic PiP-ready banner
remains removed.

## Verification

- Focused simulator-free Catalyst regression passes, proving the UIKit surface
  changes between interactive and yielding states.
- Signed optimized generic-iOS Release compilation and strict nested signature
  verification pass. App and Live Activity extension are both build 96.
- Build 96 is installed in place and launched on Jet iPad; device metadata
  confirms 2.0.0 (96). No iPhone install or TestFlight upload occurred.
- Owned DerivedData, result/install bundles and device captures were removed;
  approximately 71 GiB remained free.

## Remaining acceptance

The owner confirmed every tested CS source again left the visible player controls
unresponsive. A device incident from build 95 then identified the deeper shared
cause: synchronous player-state publication during SwiftUI's `updateUIView`
created a render feedback loop until the foreground scene watchdog terminated
the app. Build 96 retained that callback behavior, so its hit-testing correction
could not resolve the lockup. Build 97 removes the loop and owns the next gate.
