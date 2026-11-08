# Fotty Sports Hub 2.0.1 (112) — private automatic-fixture consumer

1 October 2026. Owner-only signed Release installed/launched on Jet iPad.
No TestFlight upload, other device installation, tester change or public web deploy.

## Scope

Introduce validated cricket/sports caches into the shared native catalog while
keeping provider playback, football score ownership and opt-in reminders separate.
Cleared cloud lanes: PL/CL, MLB and NHL; existing cricket retains CPL/West Indies/ICC.
WNBA and website feeds remain default-off; boxing/PDC remain source gaps.
This is not universal all-sport coverage or physical playback qualification.

## Source and binary receipt

- Captured before building: `backups/release-source/2.0.1-112-owner-ipad/`;
 962 files, one history-free source commit. Immediately before installation the
 working source matches that receipt.
- Receipt commit: `93619270c255281529622addec7e8faaf330a1d5`.
- Source SHA256: `9782438089151fe2a77d958b4b9f52e736a9fd6ee8bd1198cff7f53f92ad738f`.
- Bundle SHA256: `a4e6cc6a9ac5bf5c955a3947578edb86ddbc43de7387abd085e3cf4bb634c3d0`.
- App executable SHA256: `da0f47b9c216d191030d5ab54a7a5d634488b38d6ef96215a892d083d1ffd44d`.
- Extension executable SHA256: `9ab74bcb53139e0afebd0e41135e933c5baf4bfb5928f7d43e3ee7f253d04176`.
- Official Xcode 27 (27A266a), signed app and LiveActivity extension both 112,
 strict nested signatures, valid owner-device profile/team 9W3JDBQU39,
 and all three embedded provider-key fields empty. No simulator.

The checksum scanner initially flagged the protected dashboard renderer digest.
A narrowly content-verified checksum exception preserves the full default scan;
13 offline tests, actual scanner rejection and independent security review pass.
Two packaging verification commands were corrected (extension filename and
full-profile JSON conversion), with failed temporary output removed. Final
verified build uses the same immutable source and one reused bounded output path.

## Actual device evidence

- Exact Jet iPad: `00008101-001954E20AC0001E`, iPad Air 4/iPadOS 27.0.
 Installed bundle/version independently reports com.jelani.Fotty 2.0.1 (112).
- Existing container retained; current FPL manager and Home-curation keys remain
 present and match pre-install fingerprints. Actual values/hashes are not recorded.
- New native sports cache validates 70 fixtures/31 coverage scopes, matching
 production revision `38d7b01dedac3eded81080ef407c6a7b19afb9cba33648d23c963266c1ed00df`
 and 10:15:46 UTC receipt. MLB 13 + 8 pending, NHL 57; PL/CL covered-empty;
 27 deferred lanes.
- Native cricket cache validates 67 fixtures/three lanes: West Indies nine,
 other internationals 58, CPL offseason. All lane receipts match
 `2026-10-01T10:10:46.067Z`; cache counts match their declared lane counts.
- Real landscape Home screenshot renders; exact installed process remained alive
 beyond 60 seconds. This is not proof of every tab, reminder, source switch or playback.
- Cloud source `2026-10-01.sports-fixtures-3`, version
 `dc563c36-0137-41d5-b2bf-d292634902e7`; protected PR31–33 and monitor 36847037463
 pass. Exact-version scheduled cloud execution observed at 10:10:45 UTC.

## Remaining acceptance issue

Home displays a football-verification warning from the separate legacy pipeline.
PL/CL scoped schedule probes return 200/valid current-season empty arrays. The
repository treats an empty result as requiring a premium full-season fallback
that can throw unauthorized with empty bundled keys; proxy cooldown can also
cause no-key fallback errors. Exact observed iPad error was not captured. Do not
hide the warning or claim the full football pipeline healthy; use a focused,
tested empty-response/fallback repair before shared TestFlight promotion.

Provider decoding, opt-in reminders and corrected saved-fixture interaction
remain physical acceptance gates. No shared build was changed; TestFlight stays 111.
Owned DerivedData/build logs, remote preview/tail, temporary source-scan trees,
device plist copies, screenshot and dependency symlink are removed. Durable 19 MiB
source receipt is retained intentionally; approximately 48 GiB remains free.
