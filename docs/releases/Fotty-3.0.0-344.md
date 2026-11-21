# Fotty 3.0.0 (344) — internal TestFlight

Released 21 November 2026, about 15:45 Tobago. Upload succeeded; Apple reports
the build VALID with the What to Test note set, and the upload tool added it to
Fotty Internal Smoke, which notifies its testers.

## What to Test

Live matches stay live: a missed or failed update no longer turns them into "Start unconfirmed" or "No stream listed".
If Fotty's match feed falls behind, live status, score and minute come from a backup source.
Scores no longer say "May be delayed".

## Contents since 343

- `56bc06d`: owner decision — Fotty never labels a score as delayed.
- `d478980`: owner decision — a bad read never breaks a confirmed match.
  Trigger: at 18:25 UTC Jet stored a read with almost every league
  unavailable; live Newcastle–Arsenal showed "No stream listed" and live
  Sevilla–Betis / Parma–Roma "Start unconfirmed" for ~15 minutes.
  - Confirmed scheduled/live rows survive failed, missing, older or
    disagreeing reads for 6 h after the league's last accepted read; kept
    rows are marked `retained` and show no score until a current read.
  - A confirmed LIVE match stays in play until 3 h after kickoff.
  - Unsupported leagues are no longer turned into "unavailable".
  - App ESPN live layer for stale (>12 min) or failed football leagues.
  - Diagnostics: `sports_fixture_refresh`, `sports_lane_unavailable`
    (reason), `sports_lane_recovered`, `sports_live_fallback`; live matches
    re-read every 2 minutes.
  - Replay test from Jet's real 18:25 snapshot.
- `28d197f` (Worker, deployed separately as 0a92e849, rollback 7df94532):
  collection failures keep accepted facts; public read 2.5 s + 3.5 s retry
  with logging (was a silent 1.5 s timeout); `/api/sports/history` keeps 60
  refresh outcomes per group (first real catch: NHL HTTP 429 at 19:22 UTC);
  sports monitor every 10 min with history and ESPN in-play checks.
- `ab47bb4`: build number 344.

## Qualification

- Release source `ab47bb4`: full `tools/ios-ci.sh` passed — 2,653 tests,
  0 failures; visual regression passed.
- Worker: 668 web unit tests on the baseline, 664 on the deployed lineage.
- Not observed on a device.

## Source and packaging

- Pre-archive receipt `backups/release-source/3.0.0-344`: 2,031 files,
  verified; comparison before upload passed.
- Key-free archive; app and extension 3.0.0/344, strict signature verified,
  no XCTest bundles, 2 dSYMs, background audio, AppIcon, 2 privacy manifests,
  encryption flag false, API-key fields empty. Executable SHA-256
  437d4bf8275515a190abc89e4620ca8b19651d6aae8da907047976538c10aa2a.
- Archive, DerivedData and export output removed.
