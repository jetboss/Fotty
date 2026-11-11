# Fotty 2.0.0 (54) - internal one-tap CPL release

Date: 2026-09-03. Status: **internal TestFlight candidate assigned to
Fotty Internal Smoke**.

## Scope

- Promote the owner-accepted build-53 CPL correction without changing its
  behaviour: a trusted started CPL fixture is shown as
  `On now · listed start`, without inventing a live score or result.
- When a current CPL fixture has no exact match source, one tap on `Watch`
  opens the preferred active cricket channel. Fox Cricket is preferred and
  Willow Cricket remains available as its own channel row. Exact match sources
  still take priority and Fotty does not claim confirmed channel programming.
- Preserve the complete build-51 reliability milestone, including remotely
  refreshable fail-closed CPL fixtures, team badges, playback recovery, private
  backup, FPL truth boundaries and the single production product graph.

## Release evidence

- App Store Connect independently showed build 51 as the highest existing
  upload before build 54 was allocated. Source and both Xcode targets were
  advanced to 2.0.0 (54); private build numbers 52 and 53 were not reused.
- The generated football catalog check passed and the current live provider
  identity audit passed across three reachable feeds immediately before the
  archive.
- Xcode 26.6 archived the normal Release configuration for
  `generic/platform=iOS` with two jobs. The app and Live Activity extension both
  report 2.0.0 (54), minimum iOS 26.4 and the expected bundle identifiers.
  Strict nested signature verification passed. The signed app executable
  SHA-256 is
  `96d82accd1d0510d29c95c1709caf8f3877c9bed9472364c61efc4dff7b36d61`.
- Apple's internal-only upload returned `Upload succeeded` and
  `EXPORT SUCCEEDED` at approximately 20:33 AST. Processing completed, the
  unchanged built-in-encryption-only declaration was saved, focused English
  (U.K.) testing notes were saved and only `Fotty Internal Smoke` was assigned.
  The build detail independently shows one internal group with three existing
  testers. A fresh group read reports nine builds and build 54 as **Testing**.
- All task-owned archive, DerivedData, export and distribution-log artifacts
  were removed. Free disk remains approximately 33 GiB. No simulator, direct
  device install, external TestFlight group, App Store submission, service
  deployment, Git commit or publication occurred.

## Tester access

- At the owner's direction, App Store Connect invitations were sent to
  `akiellejackson@gmail.com` and `kirbybenjamin1996@gmail.com` using the
  qualifying Marketing role, with only Fotty selected in the one-app chooser.
- These are pending App Store Connect account invitations, not yet internal
  TestFlight group memberships. Apple will expose them to the group picker only
  after each invitation is accepted. Email receipt, acceptance, TestFlight
  delivery, installation and physical use are not inferred.

## Acceptance boundary

Build 53 has exact owner-iPhone acceptance for the changed CPL label and one-tap
routing during a current match. Build 54 is the separately signed TestFlight
artifact with the same behaviour, but exact TestFlight installation and tester
feedback remain open. Fox/Willow availability is time-varying provider evidence,
not a permanent programme guarantee.
