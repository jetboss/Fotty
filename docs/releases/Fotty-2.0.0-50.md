# Fotty 2.0.0 (50) - private iPhone 16e Graphify candidate

Date: 2026-09-01. Status: **installed only on the connected iPhone 16e; not uploaded**.
Shared internal TestFlight remains 2.0.0 (48).

## Scope

Build 50 is the first physical-device package of the current Graphify-led
cleanup and optimization source. It includes the supported-product dead-code
removal, the FPL persistence/derived-state split and the playback
recovery/source-policy split. It also contains the badge correction previously
pre-tested as private build 49.

`FPLAdvisorViewModel` remains the only observable FPL state/request owner, and
`LivePlayerViewModel` remains the only mutable AVPlayer/WebKit/proxy/task/PiP
owner. The extracted collaborators are persistence or pure decision modules,
not competing state stores.

## Device and provisioning

- Target: physical iPhone 16e (`iPhone17,5`) on iOS 26.6, connected by cable.
- The phone was initially visible but unpaired. Standard CoreDevice pairing
  completed after the owner authorized installation; the device then reported
  wired, unlocked, Developer Mode enabled and prepared.
- Fotty was not previously installed, so this was a clean first install rather
  than an in-place data migration.
- The first signed generic Debug artifact passed compilation and seal checking,
  but iOS rejected its old embedded development profile because the new device
  was not listed. No partial app install occurred. A single device-targeted
  rebuild with automatic device registration refreshed provisioning and
  installed successfully.

## Evidence

- Season-labelled reference generation passes.
- Deterministic provider identity vectors pass, and the live metadata audit
  passes across all three reachable feeds.
- The complete Mac Catalyst policy suite passes without a simulator or UI-test
  runner.
- A signed device-targeted Debug build passes strict signature verification.
  The main app and Live Activity extension both report 2.0.0 (50).
- CoreDevice independently reports `com.jelani.Fotty` as 2.0.0 (50), launches
  the normal app and observes its process continuously for 60 seconds.
- The generic physical-iOS Release graph compiles after installation.

All Xcode products were confined to cleanup-controlled temporary roots and
deleted after use. No simulator, device UI-test helper, TestFlight upload,
tester change, server deployment, Git commit or publication occurred. The
owner iPhone and Jet iPad were not changed.

## Acceptance boundary

Installation, identity and foreground process health are proven. Build 50 is
not yet physical acceptance for iPhone 16e layout, retained preferences,
playback controls, live-provider decoding, native PiP/background continuity,
notifications, FPL workflows, accessibility or the encrypted Files backup.
Those require normal manual use on this exact device. Any changed later device
or TestFlight candidate must use build 51 or higher.
