# Fotty 2.0.0 (51) - internal TestFlight reliability candidate

Date: 2026-09-03. Status: **Internal / Testing for Fotty Internal Smoke**.
Build 51 is also installed privately on Jelani's iPhone. App Store Connect
independently shows the shared build available to the existing internal group,
which now contains three testers.

## Scope

Build 51 adds the independently refreshed CPL 2026 schedule to the complete
local build-50 milestone. Fotty requests the existing Cloudflare Worker,
accepts only a complete validated 39-match manifest, preserves a newer
last-known-good device cache and falls back to its bundled schedule offline.
Completed T20 rows expire after eight hours rather than lingering for 36.

Schedule truth remains separate from stream availability. Official CPL data and
its explicit correction are authoritative; Cricbuzz is an independent current
verifier. Their known five-hour Match 28 disagreement retains CPL's official
14:00 UTC start and cannot silently overwrite the app.

## Activated services and repository

- Production Worker source: `2026-09-03.cpl-fixtures-3`.
- Cloudflare version: `2b988894-e84a-45ac-b60f-23e2a8eac498`.
- Protected publication: PR #16, merged as `d97140f` after repository, web,
  simulator-free iOS and CodeQL gates passed.
- Published monitor proof: manual workflow run `33764542003`, successful on
  `main` with the current manifest unchanged.
- Default workflow permissions remain read-only. Actions PR creation is enabled
  so the pinned monitor can propose a durable manifest update; it does not
  approve or merge that update.

## Device and evidence

- Target: Jelani's iPhone 15 Pro Max (`iPhone16,2`) on iOS 27.0 with Developer
  Mode enabled. The device was selected explicitly; the 16e and iPad were not
  changed.
- The build and install used the bounded, trap-cleaned physical release root,
  two Xcode jobs and no simulator or UI-test runner.
- Strict app signing passed. CoreDevice independently reports
  `com.jelani.Fotty` as 2.0.0 (51), launches the normal app and observes its
  foreground process continuously for 60 seconds.
- The exact CPL source passes the live three-source audit, 71/71 web/Worker
  tests, focused lint, Worker dry-run and the clean-repository hosted iOS gate.
  Production health/route smoke returns the exact Worker source, 39 fixtures,
  verified status and official Match 28 start.

## Apple distribution record

- The first archive used the installed Xcode 27 beta and passed Fotty's version,
  bundle and strict-signature checks, but App Store Connect rejected that
  delivery as an unsupported Xcode/SDK version before creating a TestFlight
  build. Build 51 therefore remained reusable.
- Apple currently lists Xcode 26.6 (`17F113`) as the supported public release.
  Its matching Apple-silicon iOS 26.5 platform component was installed because
  the lightweight Xcode installation could not compile Fotty's asset catalog or
  expose the generic iOS destination without it. No simulator was booted or used.
- A fresh Xcode 26.6 Release archive for `generic/platform=iOS` passed strict
  signing. The app and Live Activity extension both report 2.0.0 (51), minimum
  iOS/iPadOS 26.4 and the expected bundle identifiers. Archive executable
  SHA-256: `f0d7b605aef2675126e0b4ec4aa39ccb3897e60e310ce2ca308dbf8f39ebe306`.
- Xcode's internal-only export reported `Upload succeeded` / `EXPORT SUCCEEDED`
  at 18:07 AST. App Store Connect then reported the upload **Complete** and the
  build moved from **Missing Compliance** to **Ready to Test** after the same
  built-in-encryption-only declaration used for prior internal builds.
- The owner then explicitly approved the English (U.K.) testing notes, assignment
  to only `Fotty Internal Smoke`, and addition of the accepted CPL tester account
  `kevon.samuel32@gmail.com`. The account already had the qualifying Marketing
  role and app access, so its permissions were not broadened. App Store Connect
  now reports build 51 **Internal / Testing**, `Fotty Internal Smoke` with three
  testers and eight builds, and Kevon Samuel as **Invited**. Email receipt,
  installation and interaction acceptance are not yet proven.
- Apple's user page labels the current app scope `All Apps`; its selector contains
  only Fotty (`com.jelani.Fotty`) because this account currently has one app. The
  label cannot distinguish an explicit one-app selection today, so the scope must
  be reviewed before any second app is added to the developer account.

Every task-owned archive, DerivedData/export root, failure result bundle and
distribution-log bundle was removed after use. The reusable 8.52 GB iOS 26.5
Xcode component remains installed for supported future uploads; free disk after
cleanup is approximately 33 GiB. No simulator or device UI-test runner ran, and
no iPad or connected-phone installation occurred during the TestFlight upload.

## Acceptance boundary

Installation, identity, server reachability and foreground process health are
proven on the earlier private build-51 installation. Group availability is now
proven for the exact TestFlight artifact; physical tester acceptance is not.
Testers should confirm that a normal Home refresh shows the expected
upcoming CPL rows and that a source-backed CPL event opens playback. Those
interactions, plus current-provider availability, are not proven by the build or
process hold.
