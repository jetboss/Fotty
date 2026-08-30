# Fotty 2.0.0 (46) - single product graph correction

Date: 2026-08-30. Status: **Internal / Testing - available to Fotty
Internal Smoke**. Apple independently showed build 46 as Testing with the
existing internal group and its unchanged two testers at 09:14 AST.

[Apple build 46](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/abe68f67-9b20-45c2-bdfa-628a642664a9).

## Release purpose

Build 45 exposed the retired review-safe labels `Field Events`, `Reference`,
`Division A` and `Series C` during normal TestFlight use. Build 46 removes that
alternate product graph instead of adding another transition workaround.
Debug, Release and TestFlight now use the same Home, catalog, Matchday, FPL and
playback graph with truthful sport and league names.

This internal release does not add testers or roles, submit an external beta or
App Store version, deploy the website or Worker, use a simulator, make a paid
Coach request or publish the repository.

## Qualification and binary evidence

- The exact-source Catalyst unit run executed 220 tests: 219 passed, one
  existing opt-in HLS test was skipped and none failed.
- The focused product-vocabulary test and app/project retired-symbol scan pass.
  The normal generic iOS Release compile passes without a simulator.
- The Home Catalyst UI target compiled, but the beta-Mac runner timed out while
  enabling automation on two bounded attempts before executing a test. No UI
  pass is claimed; physical TestFlight acceptance remains required.
- The signed app and Live Activity extension both report 2.0.0 (46), their
  expected bundle identifiers and minimum iOS/iPadOS 26.4. Deep strict code-sign
  verification passes.
- Source/config/test fingerprint:
  `01cb09a24fdcfb716f1642e54c904c971daaa0d83455dac397fc349b0daa2a84`.
- Archived Fotty executable SHA-256:
  `9ddd57fb9dd5436d3523567418d6d89f915f4fcd741f4d07a68284777a923054`.

## Apple distribution record

Xcode 27.0 uploaded the internal-only archive successfully at approximately
17:56 AST on 2026-08-29 and reported `Upload succeeded`. App Store Connect then
completed processing. After the owner's action-time approval, the built-in
Apple encryption-only declaration, English (U.K.) testing notes and only the
existing Fotty Internal Smoke group were saved. A fresh builds-page read shows
build 46 **Internal / Testing**, the expected group and two invitations.

The testing notes ask testers to verify the normal Home/Matchday/FPL/Settings
tabs, real sport and league vocabulary, source-backed Watch behavior, retained
preferences and one clearly labelled build-46 TestFlight report. Known provider,
score, CPL snapshot, FPL draft, PiP and minimum-OS limits are stated.

## Device installation status

At 09:18 AST, a direct CoreDevice read confirms the connected Jet iPad now has
2.0.0 (46). This certifies installation only, not launch, retained data or UI
acceptance. Jelani's iPhone still reports 2.0.0 (44) after TestFlight was opened
again and remains pending its **Update** action. Do not claim build-46 iPhone
installation or complete two-device acceptance until a later version read.

## Resource cleanup

The one `/private/tmp/FottyTF46.*` DerivedData/archive/export root and its
separate Xcode distribution-log bundle were removed immediately after upload.
No task-owned build 46 temporary path remains. Disk reports approximately
53 GiB free after cleanup.
