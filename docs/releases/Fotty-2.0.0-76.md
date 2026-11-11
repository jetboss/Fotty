# Fotty 2.0.0 (76) — private native PiP correction

Date: 2026-09-06. Status: **physically rejected on Jelani's iPhone; not uploaded
to TestFlight and must not be promoted**.

## Outcome

Native Picture in Picture now survives the callback-order window where SwiftUI
reports the app in the background before AVKit reports PiP active. Fotty also
observes the retained `AVPlayer` time-control state, keeping the system PiP
Pause and Play buttons aligned with the app's playback and Now Playing state.
The same player item, stream attempt and playhead are retained.

## Verification and installation

- Four focused PiP lifecycle regressions pass, including the background-first
  callback order and system Pause/Play state synchronization.
- The complete simulator-free unit/Release gate and ten selected Catalyst UI
  checks passed before version allocation.
- Xcode 27 beta built one signed optimized Release app for the owner's iOS 27
  physical iPhone, using two jobs and one bounded DerivedData directory.
- Strict nested signature verification passed. CoreDevice installed the app in
  place, preserving its data container, then confirmed Fotty 2.0.0 (76), the
  main process and the Live Activity extension process.
- No simulator, uninstall, container reset, TestFlight upload, tester change or
  other-device installation occurred.
- The cleanup trap removed the owned build products and log. Disk space remained
  approximately 44 GiB free.

## Remaining physical acceptance

Start an independently decoded native cricket stream, enter PiP, open another
app for at least 60 seconds, then use Pause and Play in the PiP window. Lock and
unlock once. The same source and playhead must continue without returning to
Fotty or producing duplicate audio. Automated tests cannot press the physical
system PiP controls. The owner ran this check and build 76 failed: tapping Play
did not resume until Fotty returned to the foreground. The callback correction
remains valid but did not keep the paused live HLS network path usable in the
background.
