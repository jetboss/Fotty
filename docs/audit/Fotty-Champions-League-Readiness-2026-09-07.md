# Fotty Champions League Readiness — 2026-09-07

## Outcome

Fotty's build-80 candidate source is ready to present the
complete official Champions League schedule, reconcile it with late provider
listings and expose Watch only when a supported source exists. Protected
monitoring is active and automated release gates pass. Real match-time playback
on physical iPhone and iPad remains the final acceptance boundary.

## Implemented

- Reviewed all 36 2026/27 Champions League clubs against the production
  football-data.org feed and added the 17 missing formal-name aliases.
- Added source-free official Champions League rows to the Home/Search and My
  Matchday projections. Countdown, save and reminder behavior remains available;
  Watch is absent until a provider descriptor exists.
- Extended catalog deduplication across different provider IDs using exact
  sport, kickoff and both reviewed team identities. A source-backed provider row
  wins over a source-free duplicate, and real source descriptors are preserved.
- Added `tools/audit-ucl-readiness.mjs`, the daily provider-monitor report and a
  dedicated 30-minute match-window workflow. It fails a match from 30 minutes
  before kickoff through three hours afterward when no concrete supported
  Worker variant exists. Synthetic Legacy fallback responses count as zero;
  Admin/PPV is included because the player supports it.

## Verification

- Shared generated football catalogs: current and collision-free.
- Official live fixture audit: 144 Champions League fixtures, September 8, 2026
  through January 27, 2027.
- Live identity audit: passed across all three reachable provider feeds.
- Protected PR 21 merged as `2f7c6a13`; workflow, secret, iOS, web and CodeQL
  gates passed. The first hosted post-merge monitor passed.
- Strict Matchday 1 preflight: 18/18 official fixtures represented, all with
  three concrete resolved variants. Fenerbahçe–Roma has two upstream rows;
  Fotty's strict duplicate identity collapses them.
- Full Mac Catalyst unit/policy suite: passed without a simulator.
- Generic iOS Release compile: passed without signing or a simulator.
- Temporary Xcode output: automatically deleted; free disk remained about 50 GiB.

## Remaining boundary

- Metadata and an embed URL are not proof of decoded playback. During an actual
  match, exercise Watch, retry, source selection, pause/resume, audio and PiP on
  both physical device classes.
- Live score/minute, goal and full-time alerts remain Premier League-only by
  product policy. Five-minute match-start reminders are schedule-based and remain
  available for Champions League fixtures.
- Build 80 passes the complete simulator-free suite, public Xcode 26.6 signed
  Release compile and strict archive signing. Apple processed the internal-only
  upload, the established no-listed-encryption declaration and focused notes
  persisted, and App Store Connect shows it Testing for only the unchanged
  seven-person `Fotty Internal Smoke` group. Build 79 remains the rollback; no
  Worker deployment was required for this batch.
