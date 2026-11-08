# Fotty 2.0.0 (55) - internal Fotty Sports Hub identity release

Date: 2026-09-03. Status: **internal TestFlight candidate assigned to Fotty
Internal Smoke**.

## Product decision

The product now covers football, cricket, basketball, baseball, hockey,
tennis and other sports, so the owner approved **Fotty Sports Hub** as the
public name. The accepted F-over-pitch icon and `FOTTY` wordmark remain the
primary visual identity; `SPORTS HUB` is the clarifying descriptor.

## Implementation

- Add one iOS brand contract with the short name, wordmark, full display name
  and descriptor.
- Set the app and Live Activity extension display name to Fotty Sports Hub.
- Present `FOTTY` plus `SPORTS HUB · Your day in sport.` in Home and use the
  full name for the Settings version row.
- Update the PWA install manifest, Apple web-app title, primary page metadata,
  welcome metadata and social-preview identity. Compact web navigation keeps
  FOTTY primary and renders SPORTS HUB as a subordinate descriptor.
- Preserve every compatibility-sensitive technical name: bundle IDs, target,
  scheme and Swift module/type names, `fotty://` deep links, device storage
  keys, backup UTType/extension, service routes and signing.
- Save `Fotty Sports Hub` as the English (U.K.) App Store Connect app name.
  Apple applies that product identity to the build-55 TestFlight record.

## Verification

- Both Apple plists pass `plutil`; the main app and extension declare
  `Fotty Sports Hub`, while `com.jelani.Fotty`, `fotty://` and the private
  backup identifiers remain unchanged.
- A focused native regression checks the public/short/technical naming split,
  both bundle display names and the PWA manifest.
- Web/Worker tests pass 71/71, ESLint reports no errors and the optimized Next
  production build completes.
- The complete simulator-free native gate passes: generated football data and
  provider identity checks, Catalyst unit/policy tests and a generic iOS
  Release compile. It uses one trap-cleaned DerivedData root and no simulator.
- Immediately before release, the generated football catalog check passed and
  the current provider identity audit passed across three reachable feeds.
- Xcode 26.6 (`17F113`) archived the normal Release configuration for
  `generic/platform=iOS` with two jobs. The signed app and Live Activity
  extension both report 2.0.0 (55) and `Fotty Sports Hub`; strict nested
  signature verification passed. The signed app executable SHA-256 is
  `78b66698e84faf600802ff854c8c695c30aa678397007014b7e45d257685f3f9`.
- Apple's internal-only upload returned `Upload succeeded` and
  `EXPORT SUCCEEDED` at approximately 21:23 AST. Processing completed, the
  built-in-encryption-only declaration and focused English (U.K.) notes were
  saved, and only `Fotty Internal Smoke` was assigned. App Store Connect shows
  build 55 as **Internal / Testing** with the group's three testers.
- `git diff --check` and spelling scans pass. No misspelled brand variant was
  introduced.

## Distribution boundary

Build 55 is allocated because build 54 was already in TestFlight and changed
source could not reuse it. No direct device install, web/Worker deployment,
external TestFlight group, App Store submission or Git publication occurred.
Exact build-55 installation, preserved-data verification, iPhone/iPad layout
acceptance and live playback/PiP checks remain open. All task-owned archive,
export, DerivedData and distribution-log output was removed; disk remains
approximately 32 GiB free.

## Tester access

- At the owner's direction, App Store Connect sent an invitation to Jhamol
  Clarke at `jhamol61@gmail.com` with the Marketing role, Fotty Sports Hub as
  the only selected app and Create Apps disabled.
- This is a pending App Store Connect invitation, not TestFlight group
  membership. Add Jhamol to `Fotty Internal Smoke` only after acceptance.
  Email delivery, acceptance, TestFlight installation and testing are not
  inferred; the existing internal group remains at three testers.
