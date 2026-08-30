# Fotty 2.0.0 (45) — data and platform safety round

Date: 2026-08-29. Status: **Internal / Testing — available to Fotty Internal Smoke**.
Xcode reports `Upload succeeded` at 15:15:49 AST. Apple completed processing,
the owner saved the same built-in-encryption-only declaration used by prior
builds, and then explicitly authorized the prepared notes and existing-group
assignment. At 15:21 AST, the independent builds page shows build 45 Testing,
Fotty Internal Smoke and two invitations.

[Apple build 45](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/98e1a713-6ff9-40fb-a4bd-6b88baab2e1c).

## Authority and distribution boundary

The owner approved releasing the consolidated freshness and modernization work
through TestFlight. App Store Connect independently showed build 43 as the latest
upload and the existing Fotty Internal Smoke group on 2026-08-29; private build
44 was never uploaded. Build 45 was therefore allocated with
`tools/set-version.sh 2.0.0 45` across the app, extension and XcodeGen source.

This uses the normal `Fotty` Release scheme and the internal-only export profile.
It does not authorize a direct device install, simulator, external beta/App Store
submission, new tester or role, Worker/website deployment, paid model call or Git
publication. The minimum iOS/iPadOS version remains 26.4 because no physical iOS
18 device is available for runtime qualification.

## Included app changes

- Build 44's manager/season-scoped local FPL drafts remain separate from published
  picks, gameweek and official scoring evidence. Public publication limits and
  rejected edits are shown rather than hidden.
- Pending Coach work is conversation/context-owned. Clear, disable, disconnect or
  a changed manager/gameweek/plan invalidates stale results without a paid retry;
  deterministic scoring retains published-data and freshness boundaries.
- One reviewed 2026/27 competition manifest generates iOS/web membership for five
  domestic leagues plus UCL/UEL. Domestic inference requires both current senior
  teams, conflict markers fail closed, FPL caches are versioned/season-bound and
  empty schedule windows cannot silently borrow older fixtures.
- Privacy surfaces and the Apple privacy manifest describe active local records,
  public FPL IDs, opt-in Cloudflare/DeepSeek Coach processing and third-party web
  playback.
- Internal distribution access uses StoreKit-verified `AppTransaction` `.sandbox`
  or `.xcode` environments instead of receipt filenames. Production, unverified
  and error states remain review-safe; access is process-local and retried when
  the app becomes active.
- Obsolete Xcode bitcode settings are removed. Web/Worker dependency updates are
  source-only in this round and are not deployed by TestFlight.

## What to Test — saved in Apple, English (U.K.)

1. Update through TestFlight and confirm Settings reports 2.0.0 (45). Confirm
   saved matches, followed teams, appearance, linked FPL manager and local draft
   remain present.
2. Cold launch, background and reopen Fotty. Home, Matchday, FPL Coach and Watch
   must remain available. Report immediately if the app presents a restricted or
   review-safe surface in TestFlight.
3. In FPL Squad, switch between Published squad and Local draft, replace a player,
   refresh and reopen. The draft must persist without altering official scoring.
4. Ask Coach a current-points question, then a tactical question and follow-up.
   Clear the chat while a request is pending if practical; an old reply must not
   reappear. Check the source, freshness and uncertainty labels.
5. Check Premier League and other football discovery for correct 2026/27 league
   membership. Cup, youth and lower-division fixtures must not be labelled as a
   domestic senior-league match merely because one club belongs to that league.
6. During an active independently playable broadcast, check start, provider
   pause/resume/unmute, source retry and background/return. Send one clearly
   labelled build-45 report through TestFlight feedback.

Known limits: provider availability varies; live scores remain Premier League
only; CPL uses a dated schedule snapshot; local FPL drafts do not modify the
official game; preferences do not sync devices; PiP requires compatible native
playback. iOS versions below 26.4 are not supported by this build.

## Qualification and upload evidence

- Recent exact-source Catalyst suite: 220 executed, one existing opt-in HLS test
  skipped, zero failures (219 passes).
- StoreKit environment policy focused test passes. Normal and Review Safe generic
  iOS Release builds pass without a simulator.
- Web units 86/86, lint zero errors with 93 recorded warnings, Next 16.3.3
  production build/TypeScript check and full/production npm audits pass. Wrangler
  4.127.1 dry-run passes without deployment.
- Version-only build 45 archive uses the same app/test source. The signed normal
  archive reports matching app/extension 2.0.0 (45), bundle identifiers,
  minimum 26.4 and strict valid signatures. It is not Review Safe.
- Xcode's internal-only export/upload completes successfully at 15:15:49 AST;
  App Store Connect independently shows build 45 Complete, then Ready to Test
  after the owner's compliance declaration, and finally Testing with the existing
  group and two invitations at 15:21 AST.
- Source/config/test fingerprint (173 files):
  `d44b43cad20f0bb1a0cbe2d1f3e002756c1d905ac667fad43f8cfe157f350131`.
- Archive executable SHA-256:
  `feb43769227cb1c3673e1852a6fa50444ac51146e323d0348c4bd77683b4e652`.

The single `/private/tmp/FottyTF45.*` archive/DerivedData/export root and the
separate Xcode distribution-log bundle were removed immediately after upload.
No Fotty Xcode process or task-owned archive remains. Disk reports approximately
53 GiB free after cleanup.

## Remaining acceptance

Physical iPhone/iPad TestFlight installation and the tasks above remain user
acceptance, not automated evidence. Apple currently shows two invitations and no
build-45 installation, session, crash or feedback metrics; dashes mean unknown or
not yet reported, not measured zero. The next release decision should use actual
tester results rather than upload availability alone.
