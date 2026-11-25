# Fotty Fixture Freshness Contract — 2026-09-06

Status: implemented, production-activated and distributed in internal
TestFlight build 2.0.0 (75).

## Outcome

Fotty cannot guarantee that an upstream publisher never makes a late correction.
It can guarantee that old data is not silently presented as newly verified. The
fixture path now separates schedule content revision from verification receipt,
expires trust independently from fixture retention, preserves a stronger cached
snapshot during an outage, and surfaces an actionable warning when verification
is failed or old.

## CPL

- The Worker verifies the complete 39-match official schedule against a current
  independent verifier on every uncached request; Cloudflare caches that result
  for five minutes.
- A successful no-change verification updates `checkedAt` but preserves
  `revision`. A two-source fixture change still produces a new revision and a
  `live-verified` status. A partial, conflicting, or unavailable verification
  preserves the durable fallback's older receipt and reports `last-known-good`.
- iOS refreshes the CPL manifest at most every 30 minutes while active. A
  `verified` or `live-verified` receipt is considered current for two hours. A
  bundled/Worker fallback never claims freshness, even if its JSON is valid.
- A verified cached snapshot cannot be replaced by a lower-trust Worker fallback
  during a temporary outage. Invalid status values and structurally incomplete
  schedules fail closed.
- Home and Matchday warn when a displayed CPL schedule is not freshly verified;
  source-free schedule rows still never claim a playable broadcast.

## Premier League and Champions League

- The app continues to fetch the official football-data.org schedule through the
  Cloudflare credential boundary, with a 15-minute repository cache and an active
  polling owner.
- A failed official schedule refresh now removes old analysis fixtures from
  authoritative matching instead of republishing them with a new general refresh
  time. Provider stream listings remain usable and are separately freshness
  labeled.
- Home and football-containing Matchday plans show a refresh action when official
  fixture verification fails or its last successful receipt exceeds 30 minutes.
- `tools/audit-football-fixture-feed.mjs` validates the live season, competition,
  unique fixture IDs, teams and UTC dates for both PL and CL. The daily Provider
  Metadata Monitor now runs this contract independently of app launches.

## Evidence

- Live CPL audit: 39 fixtures; official identity and UTC kickoffs passed. The
  dedicated CPL monitor's four available runs through 2026-09-06 all succeeded.
- Live football audit: PL 2026/27 returned 380 valid fixtures; CL returned 144.
- Complete simulator-free iOS test and generic Release gate: passed.
- Web/Worker unit suite: 136/136 passed.
- ESLint: passed with zero errors. Worker dry-run: packaged successfully without
  deployment. `git diff --check`: passed.
- Xcode build output was trap-cleaned; no owned Fotty temporary roots remain and
  approximately 50 GiB is free after installing Xcode 26.6's reusable 8.52 GB
  arm64 iOS platform component.

## Release boundary

Production Worker version `e46fb1d9-06eb-4efb-8d24-ff5544e42215` now contains
the corrected receipt semantics. Clean-ancestry PR 17 is merged and protected
monitor run 34056219335 passed all three jobs. Apple processed build 75, saved
the established compliance declaration and focused notes, and shows it Testing
for only the existing seven-person `Fotty Internal Smoke` group.

No direct device install occurred. Jet iPad remains on private build 74 and
Jelani's iPhone remains on private build 70 until they update through TestFlight.
Exact build-75 installation and live hands-on acceptance remain separate gates.
