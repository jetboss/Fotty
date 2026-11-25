# Fotty 2.0.0 (92) — sport loading motion / private iPad

2026-09-08. Owner requested the sport-loader redesign and installation on Jet
iPad. No iPhone installation or TestFlight upload in this task.

## Included

Original shaded vector equipment and sport-specific motion across the shared
loading surfaces, with distinct rugby artwork and a conservative Champions
League blue/silver treatment. Home tile icons remain unchanged. Loading timing,
stream selection, controls and PiP are unchanged. No sound, haptics, downloaded
animation asset or new dependency. See
`docs/audit/Fotty-Sport-Loading-Motion-2026-09-08.md`.

App/widget versions are synchronized at 92 in the active Xcode project and
XcodeGen manifest; marketing version stays 2.0.0. No project regeneration.

## Qualification

- Generated football catalog drift and five provider identity vectors pass.
- Catalyst: **169 passed, 0 failed, 1 intentionally skipped** across
  SportLoadingTests, BetaUsabilityTests and PlaybackPolicyTests. The skipped
  reference-HLS soak is opt-in and was not run. This is focused coverage, not a
  claim that the entire unit/UI suite or physical playback was requalified.
- Native dark/light contact sheets were inspected at four phases for 12
  treatments. Tennis seams were corrected after the first visual pass.
- Moving frames must differ materially; static/repeated-loop frames allow only
  tiny native gradient rounding. Investigation measured 115 of 76,800 channels
  differing by one level with unchanged geometry. The first exact-byte tests
  failed; the corrected test compares decoded pixels with a one-level maximum
  and a 0.005 average-channel ceiling. All final checks pass.
- A generic Canvas fallback compile error was corrected before qualification.
  Existing Catalyst audio-session runtime warnings arise in PlaybackPolicyTests;
  this UI task does not change audio-session ownership.

## Delivery

- Optimized signed generic iOS Release passes. Strict app/nested-widget signature
  checks pass; both report build 92 and the app reports marketing version 2.0.0.
- CoreDevice confirms 2.0.0 (92) installed on the connected, unlocked Jet iPad
  Air 4. Launch and the 30-second hold pass; a separate process read confirms the
  main app (not merely its widget) remains alive.
- Actual iPad Home screenshot at 20:57 shows preserved interests, the current
  CPL fixture with Watch and the existing full-width portrait layout. No stream
  was started. The known separate youth/UCL catalog-label issue remains visible
  and is not reclassified by a decorative animation change.
- No device UI-test runner, simulator, iPhone install, TestFlight upload,
  preference reset, provider request policy or backend change.

Owner visual acceptance during real stream loading and physical motion/power/
performance checks remain open. Rendering tests and startup do not establish
real decoded playback, measured device hitching or battery usage.

The single owned 1.5 GB temporary gate directory (DerivedData, logs, results and
screenshots) was removed after verification; approximately 48 GiB is free again.
No user data or unrelated caches were removed.
