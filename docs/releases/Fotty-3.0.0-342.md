# Fotty 3.0.0 (342) — internal TestFlight

Released 21 November 2026, about 12:25 Tobago. Upload succeeded; Apple reports
the build VALID with the What to Test note set, and the upload tool added it to
Fotty Internal Smoke, which notifies its testers. Availability only, not proof
testers installed it.

## What to Test

When a stream drops, Fotty now gives Highfly time to reconnect instead of skipping it.
Live scores keep updating while you watch from any tab, including TV.
Live matches should no longer show "Start unconfirmed" mid-game.

## Contents since 341

- `98eba85`: Highfly fresh-link renewal gets 20 s (was a shared 6 s cap that
  cancelled every Highfly recovery in the Chelsea–Leeds soak); a football
  match playing on any tab keeps live scores refreshing; match-day timeline
  tests; private `status_contradiction` quality record.
- Worker (not in the binary, deployed separately on top of live `3c3a2e5`):
  no edge cache for schedule collection, football-data schedules per league,
  and the snapshot accepting per-league source paths. The per-league deploy
  briefly made `/api/sports/fixtures` return 503 (~16:00–16:12 UTC) until the
  snapshot fix; the app keeps its last good copy during such failures.
- `d50c108`: build number 342.

## Qualification

- Full unmodified `tools/ios-ci.sh` on release source `d50c108`: native
  versions 3.0.0 (342), pinned visual regression and all FottyTests (2,658
  executed, 2,646 passed, 12 opt-in skips, 0 failures), generic Release build.
- Soak (Chelsea vs Leeds on Jet, build 341 source): LIVE label held; the
  Highfly-renewal and live-score changes were not observed on a device yet.
- Worker: 658 web unit tests on the deployed lineage; live feed after the fix
  showed the five 15:00 Premier League matches live with current timestamps.

## Source and packaging

- Pre-archive receipt `backups/release-source/3.0.0-342`: 2,027 files,
  verified; comparison immediately before upload passed.
- Key-free archive; app and extension 3.0.0/342, strict signature verified,
  no XCTest bundles, 2 dSYMs, background audio, AppIcon, 2 privacy manifests,
  encryption flag false, embedded API-key fields empty. Executable SHA-256
  964717f43715c0922765b2f7f64c65480f3b1b43722865d7ddb40a4471e01736.
- Archive, DerivedData and export output removed afterwards.
