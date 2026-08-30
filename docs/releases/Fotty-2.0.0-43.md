# Fotty 2.0.0 (43) — reliability evidence round

Date: 2026-08-28. Status: **Internal / Testing — available to Fotty Internal Smoke**.
Worker deployment and automated qualification are complete. Xcode reports
Upload succeeded at **12:37:49 AST**. Apple completed processing by **12:41 AST**.
After the owner's action-time approval, the encryption declaration and testing
notes were saved and the unchanged two-tester group was assigned. At **12:47 AST**,
Apple independently shows build 43 **Internal / Testing** with two invites.
Availability is verified. At **13:23 AST**, Apple also shows both original testers
Installed 2.0.0 (43); physical task acceptance and feedback receipt remain open.

[Apple build 43](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/5c7d98eb-9837-4b1e-b818-8a62f46de9d4).

## Authority and scope

The owner approved the recommended next-phase order: release the existing fixes,
observe a small tester round, then use that evidence for data/Coach quality,
compatibility, recovery, personalization and branding decisions.

This build contains the five fixes in
[the complexity-fix report](../audit/Fotty-Complexity-Fixes-2026-08-28.md).
No new feature/UI redesign, paid service, tester/role change, direct device
installation, simulator, external submission or Git publication is included.
Normal Release and the existing internal-only export configuration are used.

Apple preflight independently confirmed build 42 was the latest upload and the
existing Fotty Internal Smoke group has two testers, both showing Installed 42.
Build-list sessions/crashes/feedback are dashes, not measured zeroes. Screenshot
Feedback and Crash Feedback both showed no reports. Build 43 was allocated with
`tools/set-version.sh 2.0.0 43`, updating app, extension and project source together.

## What to Test — saved in Apple, English (U.K.)

Playback recovery and trustworthy FPL scoring.

1. Update through TestFlight and confirm Settings shows 2.0.0 (43). Check that
   saved matches, followed teams, your FPL team, appearance and local plans remain.
2. On a working broadcast, pause for 30 seconds and resume from the same control.
   Try a short interruption and background/return. Report any unsolicited source
   change, hidden audio, stuck loading state or unusable control.
3. Compare Live Points with official FPL. Confirm official/provisional labels;
   missing player data must not become zero points or a confirmed substitution.
4. Ask Coach about your points, then a tactical decision and a follow-up. Check
   source/freshness and uncertainty. Scoring uses rules; strategy can use DeepSeek
   with consent. Test iPhone keyboard dismissal and iPad/large-text layout.
5. Save a future match without alerts, then explicitly enable a reminder. Check
   locked-device delivery and return without autoplay; verify Light/Dark/System.
6. Send one clearly marked test report using TestFlight's Send Beta Feedback.
   Include build, device, expected result and actual result. Preparing/copying a
   report inside Fotty alone does not submit it.

Known limits: provider availability varies and PiP requires compatible native
playback. Live scores are Premier League-only. CPL is a dated schedule snapshot.
Local reminders cannot learn changes while the app is closed. FPL changes are
local drafts, not official transactions; preferences/plans do not sync devices.

## Automated and production evidence

- Full web/Worker suite: **81 passed**, no failures. Existing Node module-type
  warnings remain. Production web build passes; original `.next` output is
  preserved/restored while temporary qualification output is removed.
- Mac Catalyst full unit suite: **191 passed, one optional live-HLS soak skipped,
  zero failures and zero runtime warnings**. Independent result summary read.
- Focused changed-surface Catalyst checks: FPL workspaces Dynamic Type and Player
  Dynamic Type both pass. The first FPL attempt failed before test initialization
  because Xcode could not enable automation; the runner's one allowed retry
  passed. Each passing UI result contains one main-thread runtime warning, and
  beta-Xcode debugger lookup messages remain. No real assertion failure was
  retried or suppressed. This is not physical-iOS or live-provider acceptance.
- Review Safe generic-iOS compilation and normal signed Release archive pass.
  App and extension both have their expected bundle IDs, version 2.0.0 (43) and
  minimum 26.4. Strict signatures pass; provider-key plist values are empty and
  compiled AppIcon declaration is present. Normal Release is not Review Safe.
- Xcode export/upload exits 0 and reports **Upload succeeded / EXPORT SUCCEEDED**
  at 12:37:49 AST. Apple first showed Processing, then independently showed
  Complete / Missing Compliance at 12:41 AST. After the owner's approval, the
  declaration advanced it to Ready to Test, the six tasks/known limits above
  were saved in English (U.K.) and verified after reload, and only Fotty Internal
  Smoke was assigned. At 12:47 AST, the independent builds page shows
  **Internal / Testing**, that group and two invites. Installs/sessions/crashes/
  feedback remain dashes, not measured zeroes. No repeat upload was needed.
- Archive executable SHA-256:
  `01e34e6d0f3aeafcce6af3aaf9c66e458c3b61f63d06dd123fadb43f58b06f79`.
- Source/config/test fingerprint (190 files, path/content SHA-256):
  `a16b9cc56743f87974eb05253781179cd627273bbe8552ac15ab047b03cd9fae`.
  Unchanged before upload, after upload and after the compatibility probe.

### Worker release

- Previous active revision: `39e913bd-d1fb-48e4-bf56-20be2ba183e4`.
- Deployed revision: **`fafdf5ed-4d37-47e6-82b8-69dd55c3e116`**.
- Wrangler 4.126.0 dry-run and deploy pass; existing Durable Object, two request
  limiters, model and route settings are retained. No new binding/migration,
  credential change or spending limit is claimed.
- Production `/health`: HTTP 200, schedule configured, score scope Premier
  League. This does not requalify API-Football's current-season plan access.
- Production Coach: null and malformed nested bodies return 400; a >48 KiB body
  returns 413. Missing manager/scoring evidence returns 200, low confidence,
  `Fotty rules engine`, unavailable data and **zero model tokens**. No real
  manager data or paid model request was submitted for these smokes.
- Tactical DeepSeek routing is covered with a stub in the passing suite, not a
  new live-model quality/cost evaluation.
- Worker source SHA-256: entry point
  `5482e169c1d5220c0c82206c078c6a52895daebc02f9663f138ba3b450290d1d`;
  request module `e58b5feaebcccfa47fee18c44832dd1aa92237e245bed846f843c194bf47121e`;
  scoring module `4cd70c179bb7d2dd4c686f80c7b29d37ccda467ecbc2cf8b51ac744d75106307`.

## Catalog and compatibility checks

The bundled CPL fixture set was rechecked against the league's
[published schedule](https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026)
and [27 July opponent correction](https://wp.cplt20.com/wp-json/wp/v2/news/20232).
The corrected 29/31 August opponents are already represented; no new fixture
change was found in this check. The displayed snapshot remains honestly dated
27 August, not relabeled as a continuously refreshed feed.

The release retains iOS/iPadOS **26.4**. After upload, an unchanged-source,
unsigned normal Release compile with an **iOS 18.0** command-line minimum passes
for app and dependent extension. No target source setting, installed app or
uploaded archive is changed. See [the compatibility assessment](../audit/Fotty-Device-Compatibility-2026-08-28.md)
for real older-device and Review Safe qualification still required.

The source contains no custom encryption implementation in the inspected paths;
the archived binary links Apple/system frameworks and Swift libraries. The
recommended Apple declaration remains the same built-in-encryption-only choice
used for 42, consistent with [Apple's documentation](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
The owner explicitly approved saving **None of the algorithms mentioned above**,
the testing notes and assignment to the existing group. All three submissions
are complete and verified; no new tester or role was added.

## Remaining acceptance and resources

[Round-one acceptance](../beta/ROUND-01-ACCEPTANCE.md) tracks exact-build iPhone,
iPad, long-session playback, reminders and a received TestFlight report. These
are not marked complete by automated tests, prior installations or this document.
New invitations wait for acceptance and owner-selected testers.

Preflight free disk: approximately **61–62 GiB**. The exit/interrupt cleanup
removed the **1.4 GB** owned DerivedData/result/archive/export root and the
separate Xcode distribution-log bundle; both paths are independently absent.
Free disk is **62 GiB**. The pre-existing 95 MB web `.next` output was restored;
temporary production-build output was removed. No large archive is retained
after release qualification; this final Apple-only step created no build output.
No existing unrelated workspace change or dirty ancestry is published.
