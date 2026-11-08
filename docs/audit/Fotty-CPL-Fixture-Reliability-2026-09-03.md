# CPL fixture reliability — 3 September 2026

## Finding

Fotty still treated the 39-match CPL 2026 schedule as a Swift snapshot manually
checked on 27 August. A schedule correction therefore required a new app build.
The merge also retained every started CPL row for 36 hours, so a completed T20
could remain visible well into the following day and look like a current fixture.

The source audit also reproduced why an unchecked scraper is not enough. CPL's
official schedule and Wisden publish Match 28 at 10:00 a.m. in Guyana (14:00
UTC), while Cricbuzz currently publishes 19:00 UTC. Fotty retains the official
time and records that exact third-party disagreement; it does not average times
or silently select the newest-looking value.

## Implemented boundary

- `web/public/data/cpl-2026-fixtures.json` is the reviewed, versioned 2026
  fallback imported by the existing Cloudflare Worker. It includes 39 contiguous
  match numbers, stable upstream IDs, UTC starts, known teams, playoff
  placeholders, provenance and narrowly documented verifier exceptions.
- `tools/audit-cpl-fixtures.mjs` parses the official CPL announcement, verifies
  the 27 July TKR opponent correction, and independently compares the current
  Cricbuzz series payload. Missing matches, unknown teams, duplicate identities,
  invalid dates, structural changes and unreviewed source conflicts fail closed.
- `.github/workflows/cpl-fixtures.yml` runs daily. When the official schedule and
  current verifier agree on a real change, it updates only the manifest and
  prepares a pull request for review. It never commits directly to `main` or
  overwrites a schedule from a partial response. The read-only provider monitor
  also reports live drift.
- `/api/cricket/cpl-fixtures` performs the same comparison at request time. When
  CPL's official data and the current verifier agree, it can return an updated
  schedule immediately without a new iOS build. If either feed is unavailable,
  oversized, malformed or newly conflicted, it returns the complete reviewed
  fallback with an explicit source status. The endpoint needs no new secret,
  Durable Object or paid provider.
- `CPLScheduleUpdater` requests the HTTPS manifest at app refresh, accepts only a
  complete validated 2026 schedule, rejects future-dated or malformed payloads,
  keeps a newer cached revision over an older response, and falls back to the
  bundled schedule offline. Stream availability remains a separate provider fact.
- A CPL row now ages out eight hours after its listed start. This covers an
  unusually delayed T20 while preventing yesterday's completed fixture from
  appearing as current.

## Verification

- The local manifest and live three-source audit pass. The known Match 28
  verifier conflict is reported while the official 14:00 UTC value is retained.
- Five Worker policy/route tests prove reviewed-conflict retention, incomplete
  and new-conflict rejection, agreed official updates, the public route, and
  explicit separation of live-verified changes from the durable fallback.
- Regression coverage proves the web manifest matches the bundled fallback,
  partial 38-match data is rejected, and a fixture is present at seven hours but
  absent at nine hours after kickoff.
- The complete simulator-free Catalyst unit suite and generic unsigned iOS
  Release build pass through `tools/ios-ci.sh`.
- The complete 71-test web/Worker suite and Worker dry-run pass. All workflow
  YAML parses, JSON shape checks and `git diff --check` pass. The Mac
  has no Go installation, so local `actionlint` could not be executed; the
  repository quality workflow remains the authoritative actionlint gate.

## Operational boundary

The pipeline is active. Protected PR #16 passed repository, web, simulator-free
iOS and CodeQL gates and merged at `d97140f`; manual workflow run `33764542003`
proved the published no-change path. The repository keeps read-only default
workflow permissions, with Actions PR creation enabled so this pinned workflow
can propose a durable manifest update; it contains no approval or merge step.

Production Worker source `2026-09-03.cpl-fixtures-3` is deployed as Cloudflare
version `2b988894-e84a-45ac-b60f-23e2a8eac498`. Health and fixture-route smoke
return that source, 39 fixtures, a verified status and Match 28 at the official
14:00 UTC start. Agreed official/current runtime changes are labeled
`live-verified`; their generated PR makes the change durable for Worker failure
and offline iOS fallback.

The consuming source is installed directly on Jelani's iPhone 15 Pro Max as
2.0.0 (51). CoreDevice verified the version, normal launch and a 60-second hold.
No TestFlight upload, iPad change or tester change occurred. Actual refresh,
fixture presentation and provider playback remain normal owner interaction
acceptance.

The 2026 schedule must not roll itself into 2027. A future season needs a new
official source, season manifest and reviewed app fallback before its monitor is
enabled.
