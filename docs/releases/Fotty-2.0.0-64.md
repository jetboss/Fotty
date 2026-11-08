# Fotty 2.0.0 (64) — private web-control acceptance candidate

Date: 2026-09-06. Status: installed on Jelani's iPhone and Jet iPad and physically
accepted for the reproduced web Pause/Play/Sources path on the iPhone; not
uploaded to TestFlight.

## Candidate scope

Build 64 supersedes private builds 61–63 for iPhone playback-control testing.
It keeps the roadmap work already present in those candidates and corrects the
two physical causes found while playing a decoded provider broadcast:

- the compact Fotty toolbar uses native UIKit buttons above `WKWebView`, giving
  Pause and Sources real touch-owning views without blocking the provider video;
- an earlier provider-surface tap used only to reveal Fotty's controls is cleared
  when Fotty issues Pause, so a provider's immediate scripted restart cannot be
  mistaken for a later user Play tap; and
- a new, genuine tap on the provider's own Play control can still resume.

This does not change discovery, fixtures, source selection, failover timing,
backend configuration, paid Coach access or TestFlight.

## Verification completed

- The complete simulator-free gate passed after the final source change,
  including the executed JavaScript regression for reveal tap → Fotty Pause →
  scripted restart rejection → later provider Play. Generic iOS Release passed.
- One automatically signed universal Debug artifact passed strict recursive
  signature verification, installed on Jelani's iPhone and launched normally.
  CoreDevice independently reported `Fotty Sports Hub` 2.0.0 (64).
- Against the decoded Groningen–Twente broadcast, Fotty Pause changed the
  transport to paused and held the same frame and `76:05` clock for more than
  4.5 seconds. Fotty Play resumed and the clock advanced from `76:07` to `76:11`.
  A second Fotty Pause followed by the provider's centre Play resumed normally,
  and Fotty returned to its `Pause` state. Sources opened the two-option selector.
- Closing the player returned to Full lineup. The build directory was removed
  by its validated exit trap; no build 62–64 temporary directories remained and
  approximately 28 GiB was free afterward.

## Remaining boundary

Jet iPad now runs private 2.0.0 (64), and CoreDevice confirms both the app and
Live Activity extension launched. Two cleaned physical UI attempts selected the
first current Watch listing but failed at `The live player did not open`; neither
reached or tested the controls, so this is provider-selection ambiguity rather
than a control pass or failure. No UI-test runner, result bundle, DerivedData or
install delta remains. Repeat Pause/Play/Sources and audible close on a known
decoded iPad stream before treating the fix as cross-device accepted. Broader
PiP/background, backup, accessibility and received-feedback gates remain separate.

Shared TestFlight remains build 55. No backend, production configuration,
tester, remote Git state or paid-Coach state changed.
