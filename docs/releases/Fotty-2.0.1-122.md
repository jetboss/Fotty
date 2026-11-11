# Fotty Sports Hub 2.0.1 build 122 — private iPhone UI test gate

5 October 2026. The owner authorizes installation on Jelani’s iPhone 15 Pro Max
for testing. This narrowly reopens the previously ended phone gate. The normal
connection is wireless; a cached unavailable device is not evidence that a cable
is required. No TestFlight upload or additional device is authorized.

## Included changes

- Nonblocking Inline stream-resolution feedback, visible Cancel and protected
  lookup ownership across navigation/modal transitions.
- Reminder confirmation with one-use Undo/Dismiss, current-fixture validation
  and accepted reschedule handling; no automatic notification opt-in.
- Refined sport-specific loading motion across the recognized artwork family,
  explicit secondary equipment art, correct table-tennis/Formula1 aliases and
  Watch Two preparation/per-pane loading. No playback transport/PiP changes.

Detailed source and native-art evidence is in the 5 October decision-log entries.

## Local evidence

- Before the metadata-only 121→122 increment, the final simulator-free gate
  passes 788 tests: 786 passed, two optional skips, zero failures. Unsigned iOS
  Release passes. Fresh native ImageRenderer art at full/inline scales is
  inspected in light/dark; these are not current physical-device screens.
- App/extension Debug/Release versions and project source coherently read
  2.0.1 (122). Seven native-version-verifier tests and project lint pass.
- Bundle identities and signing team remain unchanged. Source preflight finds
  no new reset path; this is not equality proof for the installed device's data.

## Installation state

The 5 October attempt passes signed Release/signature/compiled-metadata checks
but the phone stays offline. Pre-install inventory fails4016; no installation
or launch occurs. Its cleanup trap removes owned output;28GiB free remains.

On 6 October the owner reports the phone connected. Fresh discovery confirms
Jelani's iPhone15ProMax/iOS27.0.1, initially visible but unpaired. A standard
CoreDevice pairing request succeeds; fresh device details report paired,
connected, Developer Mode enabled and wired transport. No cable requirement,
unpair/reset, device substitution or network-setting change is imposed.

Rebuilt signed generic-iOS Release passes with official Xcode27/jobs1. Strict
deep signatures, compiled app2.0.1(122)/extension122 and blank embedded provider
keys are verified. Pre-install inventory reads121; in-place installation succeeds.
An inventory formatting check then rejects the column CFBundleVersion; correcting
the diagnostic column to bundleVersion confirms the installed app is122 without
rebuilding/reinstalling. Normal launch succeeds and repeated process checks show
Fotty running. A fresh native device screenshot shows the Home catalog, club
badges, sport artwork and navigation; this is launch evidence, not animated
lookup, reminder Undo, multi-view or playback acceptance.

Owned signed app, DerivedData and launch screenshot are removed;27GiB free
remains. No TestFlight upload or additional device installation occurs.

## Boundaries

Install normally in place; do not uninstall/reset the app or erase settings.
Do not capture private FPL IDs or claim retained records without inspection.
Physical motion, light/dark, large text, Cancel/Undo and provider controls remain
owner-test acceptance, separate from the successful install/launch and source/art
checks. Shared121 remains unchanged.
