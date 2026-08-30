# Fotty Web Production Audit - 2026-06-02

Scope: Home, Live Board, TV Guide, Tables, Watch, and World Cup Hub as a production sports match-day app.

## What Changed

- Added `web/src/lib/fixture-normalization.ts` so fixture titles and team labels are cleaned once before the UI renders them.
- Normalized `/api/matches` output so provider placeholders like `Home`, `Away`, `Team 1`, and `Team 2` do not become public fixture names.
- Removed server-formatted kickoff text from match subtitles. Pages now format from canonical `startsAt` timestamps.
- Updated kickoff formatting to prefer the viewer browser timezone, with `America/Port_of_Spain` as the fallback.
- Replaced public prototype copy including `Fotty 2.0 concept`, `MVP product lane`, and `MVP promise`.
- Improved TV Guide empty states for no channel matches, unmapped backup channels, and verified channels with no listing in the selected window.
- Improved Home fixture empty state with clear next actions to Live Board and TV Guide.
- Improved signed-out/watch-gated copy with value, access explanation, and next actions.
- Replaced World Cup group placeholders with intentional updating states and readiness copy.

## Route Issues And Fixes

### `/` Home

- Issue: Public hero badge used prototype language: `Fotty 2.0 concept`.
- Fix: Replaced with `Match-day ready`.
- Issue: Fixture cards could fall back to `Home v Away`.
- Fix: Home fixture rows now use the shared fixture normalization layer and show `Fixture details updating` when provider names are not trustworthy.
- State coverage:
  - Loaded: featured match, watch queue, live board links.
  - Empty: shows an intentional state plus Live Board and TV Guide actions.
  - Updating: local update banner remains lightweight.

### `/swarm` Live Board

- Issue: Feed data could contain placeholder team labels from providers.
- Fix: `/api/matches` normalizes fixture names before the board receives data.
- State coverage:
  - Loaded: live, soon, and backup sources.
  - Empty: existing board filters still need visual review after a live feed outage.
  - Stream available/no stream: watch confidence remains visible, but stream health should continue to be audited during real match windows.

### `/guide` TV Guide

- Issue: `No listing in this time window` and `No verified guide mapping yet` were too terse and felt broken.
- Fix: Replaced with clearer states:
  - Verified mapped row: `No verified listing in this window. Try Now or refresh.`
  - Backup/unmapped row: `Guide mapping pending. Stream may still be playable.`
- Issue: Filter combinations could show no rows without a clear recovery path.
- Fix: Added guide-level fallback with Show all channels, Refresh guide, and Live Board actions.
- State coverage:
  - Loaded: mapped rows first, backup rows optionally visible.
  - Empty: explicit no-match state with reset actions.
  - Data updating: loading footer remains; pull-to-refresh still works.

### `/tables`

- Issue: Table route can still appear empty if the selected league has no available standings payload.
- Fix status: Not changed in this pass beyond route audit. Recommended next action is to default unsupported table selections to Premier League with a visible `Using closest available table` note.
- State coverage:
  - Loaded: supported football league table.
  - Empty/error: existing fallback copy should be reviewed with real API outages.

### `/watch/[id]`

- Issue: Signed-out and access-gated watch pages felt like dead ends.
- Fix: Watch gate now explains what access unlocks: best available stream, backup feeds, TV guide context, and reminders. It also exposes Back to Live Board and TV Guide actions.
- Issue: Match cards and watch context could inherit placeholder team names.
- Fix: Shared fixture normalization prevents placeholder labels from being rendered as real teams where normalized match data is used.
- State coverage:
  - Signed-out: clear sign-in value and next actions.
  - Signed-in/no access: clear live-access message and plan path.
  - No stream/source unavailable: existing player fallback remains; playback root cause still needs separate broker/provider debugging.
  - Stream available: unchanged.

### `/world-cup`

- Issue: Hub had placeholder group rows (`Team 1`, `TBD`) and feed-mapping language that felt unfinished.
- Fix: Groups now show `Official seed` and `Updating` with a production-safe explanation that standings will switch once tournament feed is confirmed.
- Issue: Featured World Cup match could show `Home` or `Away`.
- Fix: Featured match now uses the shared fixture normalization layer.
- Issue: Kickoff times need local display.
- Fix: Shared kickoff formatter now prefers the browser timezone.
- State coverage:
  - Loaded: countdown, milestones, fixture panels, groups, stories, watch list.
  - Empty/data updating: no fake teams; copy is explicit that official feed data is updating.
  - Stream available/no stream: watch status comes from normalized match feed.

## Fixture Normalization Rules

- Treat blank, `home`, `away`, `team`, `team 1`, `team 2`, `tbd`, `unknown`, and similar labels as provider placeholders.
- Parse real titles containing `vs`, `vs.`, `v`, or `@` into home/away labels when possible.
- Use `Fixture details updating` when provider data does not contain two trustworthy team names.
- Preserve real team badges when available.
- Keep canonical `startsAt` as the source for kickoff time; avoid server-formatted kickoff text in API subtitles.

## Fixed Copy

- `Fotty 2.0 concept` -> `Match-day ready`
- `MVP product lane` -> `Partner support`
- `MVP promise` -> `Partner promise`
- `No listing in this time window` -> `No verified listing in this window. Try Now or refresh.`
- `No verified guide mapping yet` -> `Guide mapping pending. Stream may still be playable.`
- `Paid access required` -> `Live access required`
- `Sign in to watch` -> `Sign in to open the stream`

## Launch QA Checklist

- Home:
  - Verify signed-in and signed-out hero states.
  - Verify no `Home v Away` card appears in the feed.
  - Verify empty fixture state links to Live Board and TV Guide.
- Live Board:
  - Verify All is the default filter.
  - Verify live matches sort above upcoming matches.
  - Verify backup channels are clearly labeled.
- TV Guide:
  - Verify mapped rows appear before backup rows.
  - Verify empty filter state exposes Show all channels, Refresh guide, and Live Board.
  - Verify local time labels match the browser timezone.
- Tables:
  - Verify supported leagues load.
  - Verify unsupported/error state does not look blank.
- Watch:
  - Verify signed-out, paid-access, source-unavailable, stream-available, and no-stream states.
  - Verify access labels do not incorrectly show Free for lifetime/Plus users.
  - Verify playback failures lead to alternate feeds or guide actions.
- World Cup:
  - Verify countdown and opening milestone time in local timezone.
  - Verify groups never show fake team names.
  - Verify reminders and watch status are available for upcoming fixtures.
  - Verify stories are fan-facing, not internal product notes.

## Verification

- `npm run build` passed.
- HTTP route checks against a fresh production server on `http://localhost:3020` returned `200` for:
  - `/`
  - `/swarm`
  - `/guide`
  - `/tables`
  - `/watch/test`
  - `/world-cup`
  - `/login`
  - `/settings`
- `npm run lint` did not pass because of a pre-existing error in `web/e2e/prod-playback.spec.ts` (`Unexpected any`). Current changes did not introduce that error.
- The original `npm run smoke` target at `localhost:3000` hung before returning route results; fresh route checks on port `3020` succeeded.

## Remaining Launch Risks

- Playback/broker reliability remains the highest-risk area and should be audited separately with live provider windows.
- Exact World Cup schedule and group data should be backed by an official feed before public tournament launch.
- Tables need a more intentional fallback for unsupported leagues or upstream football-data outages.
- The public `/mvp` route is blocked by middleware in production but still exists in the app bundle; consider renaming it internally or keeping it admin-only.
