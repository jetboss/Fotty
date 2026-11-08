# Fotty 2.0.0 (48) - premium identity, motion and private recovery

Date: 2026-08-31. Status: **Internal / Testing - available to Fotty Internal
Smoke; physical acceptance pending**. Apple independently showed build 48 as
Testing with the existing internal group and its unchanged two testers.

[Apple build 48](https://appstoreconnect.apple.com/teams/fac3389d-7877-4992-9164-014bae4c075e/apps/6805561883/testflight/ios/70973251-4540-49e3-ad82-6474c45fef0c).

## Release purpose

Build 48 brings the completed six-step badge and contextual-motion plan into the
shared internal beta. It also consolidates the private build-47 PiP/search/
football-identity work and the owner-approved private backup flow. It does not
add testers or roles, submit an external beta or App Store version, deploy the
website or Worker, use a simulator, make a paid Coach request or publish the
repository.

## Included work

- One shared badge window now owns remote/cached artwork and a stable monogram
  fallback across the app's team-name surfaces. Football aliases and major
  NBA/WNBA/MLB/NHL/CPL/IPL coverage are audited without retaining provider
  images or adding a runtime scraping dependency.
- Football, cricket and tennis use recognisable contextual loading motion;
  other sports retain a restrained generic treatment. Continuous motion stops
  for Reduce Motion, Low Power Mode and inactive scenes.
- Settings → Privacy can export and restore a versioned local-only Fotty backup
  through the system Files picker. Import validates the document before
  replacing supported preferences and manager-scoped planning data.
- The native PiP background-continuity correction and current football identity
  pipeline previously isolated in private build 47 are part of this shared
  source. Provider playback remains time-dependent and PiP is not certified
  until a real native stream passes the physical continuation check.

## Qualification and binary evidence

- The generated football catalog is current and the local five-vector plus
  three-feed live football identity audits pass.
- The same-day artwork audit resolves and signature-checks 272/272 image URLs:
  148 source-controlled football names plus complete NBA, WNBA, MLB, NHL, CPL
  and IPL catalogs. Thirteen shared URLs are confirmed aliases of the same clubs
  and no suspicious collision remains. A later repeat was correctly blocked by
  a transient TheSportsDB 503/timeout; that provider outage is not presented as
  a fresh pass or an app defect.
- Companion web/Worker checks pass: 74/74 unit tests, zero lint errors (48
  recorded warnings), Wrangler dry-run and the Next.js 16.3.3 production build.
  Nothing was deployed.
- The exact build-48 simulator-free native gate passes its Catalyst unit suite
  and generic iOS Release compilation. No simulator, UI-test helper or direct
  device installation was used.
- The signed archive's app and Live Activity extension both report 2.0.0 (48),
  their expected `com.jelani.Fotty` identifiers, team `9W3JDBQU39` and minimum
  iOS/iPadOS 26.4. Deep/strict signature verification passes.

## Apple distribution record

App Store Connect independently showed build 46 as the newest prior upload;
private direct build 47 was already consumed, so 48 is the first safe shared
number. Xcode uploaded the internal-only archive successfully at 12:03:54 AST
and reported `Upload succeeded` / `EXPORT SUCCEEDED`. Apple then showed build
48 **Processing** at 12:03 AST. Processing completed, the owner-approved
built-in-encryption declaration and seven testing tasks/known limits were
saved, and only the existing Fotty Internal Smoke group was assigned. A fresh
builds-page read then showed **Internal / Testing**, two invitations and no
installation/session/crash/feedback metrics yet. Those dashes are unknown/not
yet reported, not measured zeroes.

## Required physical acceptance

On the exact TestFlight build 48 on both iPhone and iPad:

1. Confirm Settings reports 2.0.0 (48), retained preferences and no first-launch
   regression.
2. Check representative Football, Cricket and Tennis discovery/loading states,
   then repeat with Reduce Motion enabled.
3. Check team badges on Home, Matchday/Match Center and FPL, including Paris FC
   versus PSG, one CPL team and offline/error monogram fallback. Rows must not
   jump as artwork resolves.
4. Check Dark and Light appearance, large text and iPad width without clipping
   the sport selector, badges or actions.
5. Export a private backup to Files, inspect the confirmation summary and test
   a valid restore without losing the active manager/planning context.
6. With an active compatible native stream, keep PiP playing in another app for
   60 seconds, then lock/unlock. Confirm no pause, source replacement, duplicate
   audio or obstructed transport controls.
7. Submit one clearly labelled build-48 TestFlight feedback report. Upload or
   installation alone does not satisfy this acceptance gate.

## Resource cleanup

The single 321 MB `/private/tmp/FottyTF48.*` archive/DerivedData/export tree and
the separate Xcode distribution-log bundle were removed immediately after the
successful upload. No task-owned build-48 temporary path remains; disk returned
to approximately 47 GiB free.
