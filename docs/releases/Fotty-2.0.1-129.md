# Fotty Sports Hub 2.0.1 (129) — private Jet iPad gate

10 October 2026. Owner-approved five-part maintenance/verification pass followed
by Jet iPad testing. No phone install, simulator, shared TestFlight, Git
publication, backend deployment, spending or source/account reset is authorized.
FPL feature work remains paused.

## Implemented boundaries

1. Accessibility exceptions are exact and Catalyst-27-only. Native iOS/iPadOS
   retains Apple's default failure for contrast, Dynamic Type and unknown cases.
2. Ten deterministic component PNGs were inspected individually and explicitly
   approved. Light/dark, narrow/large layouts, long names, sources, Watch states
   and loaded/missing artwork are compared in normalized sRGB. Synthetic loaded
   artwork does not establish real club identity. Renderer/accessibility settings
   are fingerprinted; animation is disabled without changing owner settings.
3. Eight real shared-image transport/cancellation behaviours are executed with
   held transports and controlled completion. The existing cache, byte limits,
   connection limits and decode ownership are retained.
4. Search/player delays accept an injectable cancellation-aware clock. Existing
   production delays are retained; obsolete query/attempt/source/lifecycle work
   cannot acquire newer presentation ownership.
5. Passive, attempt-bound stall/audio-preparation intervals use the existing
   bounded local quality store. No private URLs, uploads or added playback owner.
   Three physical catalog metric journeys require finite app-target results;
   the two scroll journeys additionally require actual translation. Cache and
   owner selections remain intact.

The prior atomic Home coordinator and serialized audio preparation repairs are
included. Eighteen new timing/interval/Web tests execute those boundaries.

## Source and binary provenance

- Approved component source receipt:
  `0f380924e654eaf00ea183551a22ff31b1baa248fb8c02aca7bc199f0699ca83`;
  `backups/release-source/2.0.1-129-components-reviewed`.
- Pre-build source receipt:
  `ebef11030ae3050af7a640d413d06049911725a8253a972ae0dec106b30abcc5`;
  `backups/release-source/2.0.1-129`.
- Pre-build bundle SHA-256:
  `a999313854769aa9ce40ed5a0beb43444ea88f9f9ae8af373e32f56193d26e14`.
- Signed optimized Release executable SHA-256:
  `2bdb51c7ed032b848380c194d9c81df6dcdcdc93b4757ff2ea0d7cebe56af9d5`.
- Strict app/extension signature verification and version coherence pass.
  Jet iPad installed-app readback confirms 2.0.1 (129), sequence 2156.
  Source compare passes after the temporary UI-only scheme is removed and before
  these post-build documentation updates. Production Release testability is not
  enabled merely to compile unit tests; the physical runner uses a UI-only scheme.

## Verification and superseded physical gate

- Final Catalyst: 1,071 total; 1,069 passed, two existing opt-in skips, zero
  failures. Approved non-recording component comparison passes. Five offscreen
  FocusState warnings remain (four reminder tests and one component renderer);
  no audio-session runtime warning is reported.
- Offline tooling: 74 Python and nine visual-approval Node tests pass. Membership,
  version, catalog, provider vectors and diff checks pass.
- Unsigned generic iOS Release and signed optimized UI-only Release build pass
  with official Xcode 27, sequential one-job execution and one reused output root.
- The first physical attempt timed out at Apple's Touch ID automation prompt,
  before any test could run. It is not an app crash or failed interaction.
  After the owner cleared it, the authenticated gate completed: nine passed,
  four failed and two skipped. The Home contrast audit failed on the footer
  status; all three catalog metrics failed XCTest's manual-stop lifecycle and
  returned no measurements. Neither failure was waived. Build 130 repairs the
  footer readability and uses automatic interaction-block measurement.
- Production navigation/Search, source-switch/return, finished-match checks,
  Watch Two controls/soak and five accessibility-policy tests passed. Native PiP
  was skipped because no ready native layer/media-time source qualified within
  the bounded attempts. Physical lookup cancellation skipped because resolution
  completed before cancellation could be exercised. Controlled cancellation
  logic tests remain separate passing evidence, not a substitute for that skip.

Build 129 is not physically qualified. Build 130's repair gate also failed: the
Home footer remained a native contrast finding; forwarding wrappers around
Apple's CPU collector raised `Invalid parameter not satisfying: _data`; Search
timed out while XCTest waited for animation completion. No app-owned infinite
Search animation was confirmed. Build 131 removes only the redundant confirmed-
live footer, uses concrete Apple metric collectors and batches each exact Search
typing command. Its separate results belong in the build-131 receipt.
No cross-build speed improvement, decoded-frame continuity, background audio or
two audible/decoded panels is claimed by compilation or muted scalar tests.

## Cleanup

The temporary UI-only scheme is removed. Build 129 evidence is retained in this
dated receipt; its two meaningful local recovery bundles remain recoverable.
The active build-131 gate owns the same temporary output root/runner and removes
them after final evidence review. No shared TestFlight release occurred.
