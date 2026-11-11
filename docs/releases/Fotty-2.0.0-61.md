# Fotty 2.0.0 (61) — private playback-control candidate

Date: 2026-09-06. Status: installed and launched on Jelani's iPhone and Jet
iPad; exact-device Pause/Play recheck pending; not uploaded to TestFlight.

## Candidate scope

Build 61 supersedes private builds 59 and 60. It contains the four local product
roadmap batches plus the playback-control correction found during owner-device
inspection:

- web-player chrome is no longer descended from a hit-testing-disabled view;
- Fotty's explicit Pause survives a provider's immediate scripted restart; and
- a real tap on the provider's own Play control is still permitted to resume.

This is a UI/bridge correction, not a change to stream discovery, fixture
identity, failover timing, source choice, backend configuration or TestFlight.

## Verification completed

- The complete simulator-free native gate passed after the final correction,
  including the executed JavaScript monitor regression for scripted restart and
  genuine provider resume. Generic unsigned iOS Release passed.
- One automatically signed universal Debug artifact passed strict recursive
  signature verification and was installed unchanged on Jelani's iPhone and
  Jet iPad. Both installations launched normally.
- CoreDevice independently reports `Fotty Sports Hub` 2.0.0 (61) on both.
- All owned CI, physical-build, UI-runner and diagnostic directories were
  deleted. No UI-test runner remains on the iPhone. Approximately 30 GiB was
  available after cleanup.

## Physical evidence and remaining gate

The preceding build-59/60 inspection verified the iPhone Home, Matchday and
appearance flows and visually checked iPad Home in stable portrait and landscape.
It also reproduced the web Pause defect against a decoded football broadcast:
the match continued and Fotty's label remained `Pause` after the tap. Those older
observations identify the defect but cannot qualify build 61.

One physical XCTest run reached its test body but returned a failure whose
assertion was hidden by quiet Xcode output; a diagnostic rerun then reached the
device-lock preflight and was stopped rather than left waiting. That is not a
pass and it does not identify the failing step. All runners, result bundles and
diagnostics were removed. Before build 61 is accepted or promoted, authenticate
iPhone Mirroring (or keep the physical phone unlocked for the complete run) and
verify: Fotty Pause changes to Play and freezes the match;
Fotty Play resumes; the provider's own Play control can resume after a Fotty
pause; Sources remains tappable; closing the player stops its audio. Repeat the
transport controls on iPad. Broader PiP/background, backup, accessibility and
received-feedback acceptance remains open.

Shared TestFlight remains build 55. No backend, production configuration,
tester, remote Git state or paid-Coach state changed.
