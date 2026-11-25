# Fotty 2.0.0 (95) — private CS player-control acceptance

2026-09-13. Status: **rejected on Jet iPad; superseded by private build 96**.
This is a private physical-device build, not a TestFlight release.

## Included

- The post-93 optional CS source lane remains merged with Fotty's ordinary
  broadcast discovery. Exact sport, both teams and kickoff are required; the
  lane does not add or own fixtures.
- Native video taps are now handled by the underlying UIKit player surface and
  forwarded to the existing control toggle. This avoids relying on a SwiftUI
  gesture around `UIViewRepresentable` after a source switch.
- The automatic `Picture in Picture ready` banner is removed. PiP availability
  is already communicated by the PiP button and is not playback success.

## Evidence

- Provider identity vectors and the live three-feed identity audit pass.
- The exact San Francisco Giants vs San Diego Padres CS route returned seven
  candidates. CS1 returned a valid HLS master playlist with 1080p and 540p
  variants.
- Signed optimized iOS Release builds 94 and 95 compile and pass strict nested
  signature verification; app and Live Activity extension versions match.
- Build 94 installed on Jet iPad and an on-device capture showed the CS-selected
  MLB video frame. The Fotty process was alive, disproving the apparent crash,
  but the hidden control surface could not be restored reliably.
- Build 95 is installed in place on Jet iPad as 2.0.0 (95). Temporary DerivedData,
  result bundles, install bundles and the diagnostic screenshot were removed;
  approximately 71 GiB remained free.

## Remaining acceptance

Owner retry found that the native surface still owned hit-testing after controls
appeared, so none of the visible buttons responded. Build 96 makes ownership
dynamic and is the next private acceptance candidate. No iPhone install or
TestFlight upload is included here.
