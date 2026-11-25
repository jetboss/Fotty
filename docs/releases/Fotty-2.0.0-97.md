# Fotty 2.0.0 (97) — native-player render-loop correction

2026-09-13. Status: **installed on Jet iPad; physical acceptance pending**.
This private build is not uploaded to TestFlight or installed on iPhone.

## Root cause and correction

The build-95 device incident is a FrontBoard `0x8BADF00D` scene-update watchdog,
not a stream decode failure or an unusually long CS URL. Its main-thread stack
shows SwiftUI updating `PlayerUIView`, callback setters synchronously publishing
the current AVPlayer state, the observed view model changing, and SwiftUI
immediately updating the representable again.

Build 97 makes the ready-for-display, time-control-status and PiP-availability
callbacks passive properties. State is still delivered by the existing AVKit
KVO observations when the underlying value actually changes. Build 96's dynamic
hit-testing remains: the native surface owns a tap only to reveal hidden controls
and yields interaction while controls, loading, or an error are visible.

## Verification

- Simulator-free Catalyst tests pass for both callback-reassignment silence and
  dynamic native-surface hit-testing.
- Signed optimized generic-iOS Release compilation and strict nested signature
  verification pass. App and Live Activity extension both report build 97.
- Jet iPad confirms Fotty Sports Hub 2.0.0 (97) after in-place installation and
  launch. The iPhone and TestFlight were not changed.
- The owned DerivedData was removed after staging; free space remained 71 GiB.

## Remaining physical acceptance

On a CS source, keep playback open at least 15 seconds and verify Close, center
Play/Pause, Sources, PiP/fill, continued audio/video, and switching back to an
ordinary broadcast. Check for a new device incident if any control locks again.
