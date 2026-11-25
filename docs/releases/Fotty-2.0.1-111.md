# Fotty Sports Hub 2.0.1 (111) — internal polish and reliability candidate

2026-09-20. Status: **Internal / Testing in Fotty Internal Smoke**.

## Scope and authority

The owner approved deploying the current validated 2.0.1 source to TestFlight.
Use only the existing `Fotty Internal Smoke` internal group. Do not add testers,
change roles or notifications, publish Git source, create an external group, or
submit to App Review.

This candidate consolidates private builds 101–110: app-wide Apple-aligned polish,
adaptive iPhone/iPad layouts, native Liquid Glass tabs, badge-led Home hierarchy,
compact live/up-next rows, consistent sport artwork, Watch Two improvements,
interest-filter recovery, quieter truthful catalog/fixture messaging and corrected
CPL playoff identity. It retains the playback, FPL and persistence boundaries
already exercised during the private cycle.

The companion Worker is independently deployed as source
`2026-09-20.worker-stability-1`. It bounds remote calls, records structured
provider coverage, preserves a direct catalog fallback, returns the complete
reviewed CPL schedule and exposes exact-version health evidence. API-Football's
configured plan currently rejects current-season live scores, so the app must
continue using its official FPL/football-data fallbacks rather than promising
that optional minute feed.

## What to Test

This update refreshes Fotty's complete presentation while keeping your saved
interests, FPL workspace and broadcast-source settings.

Please check:

- Home on iPhone and iPad: badges, sport artwork, readable team names, Live and
  Up Next hierarchy, and the native Home/Matchday/FPL/Settings tab bar.
- Change Home interests and sport filters. `Show all sports` should recover from
  an empty selected sport, and upcoming selected competitions should remain visible.
- Open Cricket and confirm the CPL Final shows Antigua & Barbuda Falcons vs
  Jamaica Kingsmen without a permanent routine broadcast warning.
- Open a live match, switch sources, use pause/unmute when the provider offers
  them, and try Picture in Picture by opening another app.
- Try Watch Two on iPad: select two matches, change the left and right sources
  independently, and move audio focus without shrinking or freezing either feed.
- Reopen the app and confirm appearance, interests, followed matches and the FPL
  manager/workspace are retained. In FPL Coach, dismiss the keyboard and confirm
  the answer remains visible.

When reporting a problem, include build 111, device, sport/match, the visible
source label and what happened. Do not include private stream URLs or credentials.

## Qualification plan

- Pin official Xcode 27 (27A266a); never use a simulator.
- Capture and verify the immutable pre-build source receipt.
- Run current provider identity, full simulator-free iOS CI, Worker/web tests,
  lint, Worker dry-run, production web build and live Worker contract monitor.
- Build one generic iOS Release archive with automatic signing and two jobs.
- Verify app/extension version, identifiers, signatures, SDK, deployment target,
  dSYMs, production configuration, empty embedded provider keys and source receipt.
- Upload using the internal-only export profile, then separately verify Apple
  processing, encryption declaration, focused notes and existing-group assignment.
- Remove owned DerivedData/archive/export/log output after completion or failure.

## Acceptance boundary

Upload success is not exact-build physical acceptance. After Apple marks 111
Testing, install it through TestFlight on an iPhone and iPad and repeat the checks
above. Active-provider playback, PiP/background continuity, retained data and one
received tester feedback report remain the gates before widening the beta.

## Qualification and upload evidence

- Official Xcode 27 (27A266a) was pinned for every native command. The complete
  simulator-free iOS CI gate passes, including Catalyst policies and generic iOS
  Release compilation. No simulator or direct device installation was used.
- Live football identity passed across one reachable feed while both StreameX
  catalog hosts were unavailable. PL and Champions League schedules returned
  complete current-season feeds. The reviewed 39-row CPL manifest and its known
  match-28 verifier exception pass. Production Worker source
  `2026-09-20.worker-stability-1` passes health, CPL, catalog-fallback and embed
  contracts without consuming a live-score quota call.
- All 149 web/Worker units, lint, Wrangler dry-run and the optimized Next build
  pass. Catalog coverage remains truthfully partial at one of three metadata
  providers; the direct playback fallback remains present.
- The signed archive reports 2.0.1 (111), arm64, minimum iOS 26.4 and SDK
  iphoneos27.0. App and Live Activity extension identifiers, versions, team
  `9W3JDBQU39`, strict signatures and dSYMs match. All three provider manifests
  match source; Assets.car and background audio are present; provider API-key
  fields are empty; no test bundle/framework is packaged.
- Source receipt commit `9497a144bec20597d7cd2122371922d36a2d36da`, source
  SHA-256 `cb5f17aaffdeb4d5e264f1bb409c322209846dc118c19a1693a5935dab35caaf`
  and bundle SHA-256 `4e399c0682ba42a8d7c434ce26a88e94c50c7e081680c0e844ad3bd015645bb7`
  were captured before build and matched immediately before upload.
- Archived app executable SHA-256:
  `0b0b2bf217e6ffb6459aed0794ff9634af9724dd926ce49faedfded4adebbb44`;
  extension executable SHA-256:
  `aaf3d6a159fadd5f2e620b0c5a93e4305ebc349bd93d608610516757e6a2d6ec`.
  Their UUIDs are `E6EDA9CE-C2F9-3DFF-94CD-6F66306EA01D` and
  `0CAC8B59-B5E2-3CE5-8CCB-C9BAEE6A41F3` respectively.
- Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED` at 12:52 AST. Apple
  completed processing, accepted the established no-listed-encryption
  declaration and showed build 111 as `Testing` at 12:57 AST. The focused
  English (U.K.) notes are saved and only the existing 11-person
  `Fotty Internal Smoke` group is assigned. Build 100 remains available as the
  fallback; no tester, role, notification preference, external group or App
  Review state was changed.
- The single owned archive/DerivedData/export root and Xcode distribution log
  were removed. Disk returned to approximately 59 GiB free. The source receipt
  under `backups/release-source/2.0.1-111/` is intentionally retained.
