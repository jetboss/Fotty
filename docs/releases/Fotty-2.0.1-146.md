# Fotty 2.0.1 (146) — native fullscreen, private Jet iPad gate

13 October 2026. Installed and read back as 2.0.1 (146) on Jet iPad Air4,
iPadOS27.0.1. Phones125/shared TestFlight121 are unchanged. No release, backend
deployment, Git publication or provider-policy change is authorized by this gate.
FPL is unchanged. The Apple UI design skill guided native media controls rather
than replacing the approved retained viewing experience with custom fullscreen.

## Implemented contract

- Fullscreen presents the actual AVPlayerViewController with Apple controls.
  Focus/Companion remain separate actions and retain the new viewing experience.
- NativeFullscreenSession is a presentation lease over the existing player,
  current item, selected source and attempt. Entry/Close do not load, seek,
  replace or autoplay a stream. Explicit paused intent survives re-entry.
- The retained inline view stays mounted but detaches its renderer and PiP
  ownership while AVKit presents. Actual window/scene and current-owner guards
  fence deferred presentation, transport, readiness, dismissal and PiP callbacks.
- A stale nil presentation update cannot retire a newer lease. Model-owned rate
  commands cannot become user Pause/Play commands. Failed PiP restoration leaves
  dismissal state intact; only successful restoration clears it.
- Test-only ready/time receipts share exact player/item identity across temporary
  inline detachment. Reading a temporarily absent inline player cannot reset the
  token or bind an unavailable measurement to a different owner.

## Local qualification and provenance

- Full current-source Catalyst suite: 1,302 tests, 1,300 passed, two existing
  optional skips, zero failures. Eighteen new fullscreen regressions cover
  ownership, pause intent, stale callbacks, repeated presentation and measurement
  identity. Existing FocusState fixture warnings remain; no simulator was used.
- Signed native Release app/extension and physical UI harness compile; strict
  signature, source comparison, install and actual version readback pass.
- All 42 FPL Swift source hashes match the starting state. No FPL settings or
  phone interaction was used during the tests.
- Pre-build source receipt: backups/release-source/2.0.1-146-native-fullscreen,
  captured20:35:42UTC, commit08a9000c045bd29844ee094411ee51c346bd2b92,
  sourceSHA25669f7c82c1525f97a334528b80872e2acf7217752de638a18b87955154980f523.
  All1,105 source inputs compared before build/install. A final read-only review
  confirms every production/config/asset input still matches. Subsequent edits
  are UI-test harness and acceptance documentation, not production changes.
  Final UI harness SHA256:
  f3437815839af4f3b377a92f6628d35acd279c4e8395f888cba6642f08355aff.

## Physical evidence, limitations and earlier failures

- Jet146FullscreenBufferCheck passes: real Atleti–Manchester United CS6 decoded
  native video, two actual AVKit fullscreen presentations/Close returns, deliberate
  paused re-entry, actual Apple Pause/Play, repeated pause/play, advancing restored
  inline video and Stop. Exact player/item/attempt identities remain equal.
  The actual landscape AVKit controls and restored companion layout were inspected.
- Initial eight-second Resume qualification failed with rate1/status-waiting,
  not rate0. The existing native buffer target is12s. A bounded30s progress check
  passes without changing production pause intent, buffering or provider rules.
  This does not prove a general provider-only cause or a guaranteed startup time.
- CS1 native fullscreen PiP survives60s on the real Home screen. After returning
  to Fotty, the same player/item/attempt advances65.597s (53.928→119.526), rate1.
  Actual floating video is visible. OS Restore lookup remains unqualified: the
  floating surface appears in XCTest but its real Restore button is not exposed.
  An existing measurement behind PiP is not restoration proof; success requires
  PiP to close, the same fullscreen owner, ready video and advancing media time.
- A separate CS6 PiP run stalls before requesting PiP; its inline source is
  already buffering before fullscreen. No CS6 PiP request or background pass is
  claimed, and causation by fullscreen is not established.
- A later exact CS1 repeat skips because the finished football fixture is no
  longer watchable. No fixture, channel or stale source was substituted into that
  community-source acceptance gate.
- A separate normal-broadcast/explicit Willow native PiP setup also skips after
  bounded alternatives: no ready advancing native layer qualified. It is not a
  CS pass, a PiP request or evidence of a new production fullscreen failure.
- Physical XCTest deliberately mutes streams. These checks are not audible,
  continuous-frame, blanket provider uptime, portrait-rotation or cross-device
  proof. Prior sync/widget/Watch Two acceptance gates are not cleared by fullscreen.

## Remaining acceptance

Complete actual system PiP Restore→native fullscreen→Close→inline progress on an
available real native broadcast. Do not alter source eligibility, buffering or
production controls to work around OS accessibility. No TestFlight qualification
or release is implied by the bounded native fullscreen pass.
