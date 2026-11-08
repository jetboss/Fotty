# Fotty 2.0.0 (75) — fixture freshness and daily-use internal beta

Date: 2026-09-06. Status: **Internal / Testing** for `Fotty Internal Smoke`.

## Outcome

Build 75 consolidates the privately exercised builds and the four reliability
batches after TestFlight build 55. The shared beta now includes the personalised
three-day Home, audience-led live ordering, catalog performance work, one-tap
cricket discovery, playback-control/lifecycle fixes, connected Matchday flows,
the current FPL workspace and honest fixture-freshness state.

Fixture freshness is active end to end. CPL content revisions no longer double
as verification receipts; retained fallbacks cannot appear newly current or
downgrade a verified cache. Premier League and Champions League official-feed
failures remove stale analysis authority and surface a refresh action while
independent broadcast listings remain usable.

## Production activation

- Clean-ancestry pull request [#17](https://github.com/jetboss/Fotty/pull/17)
  merged to `origin/main` as `47c5e097d98010fda121f030c29e83182c8a4077`.
- Cloudflare Worker `fotty-playback-v3` deployed version
  `e46fb1d9-06eb-4efb-8d24-ff5544e42215` with source version
  `2026-09-06.fixture-freshness-1`.
- Production CPL returned `verified`, 39 fixtures, revision `2026-09-03.1`
  and receipt `2026-09-06T19:51:55Z`. The known Match 28 review warning was
  retained rather than hidden.
- Provider Metadata Monitor run
  [34056219335](https://github.com/jetboss/Fotty/actions/runs/34056219335)
  passed CPL, PL/CL fixture and provider-identity jobs. Live full-season checks
  returned 380 Premier League and 144 Champions League fixtures.

## Release verification

- App Store Connect showed build 55 as the latest upload before build 75 was
  allocated with `tools/set-version.sh`.
- Public Xcode 26.6 (`17F113`) was used explicitly. Its lightweight install
  required Apple's reusable 8.52 GB arm64 iOS 26.5 platform component; no
  simulator was created or started.
- `git diff --check`, current live fixture/identity audits, the complete
  simulator-free Catalyst unit/policy suite and generic iOS Release compile
  passed. The version-only change after the recent build-74 UI pass did not
  invalidate that source evidence.
- The normal signed archive reported app and Live Activity extension 2.0.0
  (75), bundle IDs `com.jelani.Fotty` and
  `com.jelani.Fotty.LiveActivityExtension`, and minimum iOS 26.4. Strict nested
  signatures passed. Signed executable SHA-256:
  `918d3e1d380e424367bdc655bc3a215696799c01a06c461505d3631991fc357f`.
- The internal-only export returned `Upload succeeded` and `EXPORT SUCCEEDED`
  at approximately 16:19 AST. Apple processing completed, and the established
  Apple-provided-encryption declaration was saved.
- App Store Connect shows build 75 as **Testing** for the one existing internal
  group, `Fotty Internal Smoke`, with all seven existing testers. Focused
  English (U.K.) What to Test notes were saved. No tester, role or external
  group was added or removed.

## Distribution and acceptance boundary

No direct iPhone/iPad installation, simulator, external TestFlight submission,
App Store submission or dirty-worktree publication occurred. Upload and group
availability do not prove installation or hands-on behavior. On the exact
TestFlight build, verify retained Home interests, PL/UCL/CPL fixtures and kickoff
times, cold scrolling, one-tap cricket playback, controls/audio/PiP continuity,
and current FPL team/Coach evidence on at least one supported iPhone and iPad.

All task-owned DerivedData, archives, exports, Xcode distribution logs and
result bundles were removed. Approximately 50 GiB remained free; the reusable
Apple platform component accounts for the deliberate permanent disk change.
