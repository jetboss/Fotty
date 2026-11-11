# Fotty: watch-first 90-day roadmap

Approved by the owner on 10 Nov 2026. Fotty is a **watch-first** app: open
it, tap Watch on the match you care about, and it plays. Everything else
comes second to that promise.

## Principles

- **Reliability is measured, not hoped.** Every competition we promise has a
  number: share of Watch taps that reach a picture, and time to picture.
- **Ship weekly to real hands.** A small internal TestFlight group on phone and
  iPad. Each upload still needs the owner's explicit go-ahead.
- **Cut what doesn't serve watching or following your teams.** Fewer features,
  each one solid. FPL stays as its own corner and never slows Watch work.
- **Bring your own source.** Sources a person connects to their own account
  (Highfly first) are the backbone and the defensible way to distribute.
- **Device checks prove what only a device can.** Everything else runs in CI.

## Month 1: reliable, measured, shipped

| Work | Done when |
| --- | --- |
| Private Watch outcome record in the app (tap → first picture time, source used, failover, failure reason; no URLs or credentials) | Each Watch tap writes one record; Settings can export a summary |
| Cloud playback probe for PL, UCL and cricket windows (does each source still return playable HLS) | A daily report per competition and source (built 11 Nov: `tools/playback-probe.mjs`, runs once on `main`) |
| Phone parity: Home, Watch, player and Settings on iPhone | One physical iPhone pass recorded |
| Release gates green: unsigned Release, provider audit, web checks, PR to `main` | Checklist in `docs/notebooklm/Workflow.md` all ticked |
| Weekly internal TestFlight | First upload since build 206, owner-approved |

## Month 2: smaller, faster, your own sources

| Work | Done when |
| --- | --- |
| Remove review-only and dormant sources and features (PenguPlay/StreamNexus setup, unused ESPN feeds, Watch Two if unused) | Removed code, not hidden flags |
| Two-minute "add your source" flow (Highfly and future account sources) | A new tester connects Highfly unaided |
| Highfly name matching for national teams and common aliases | Internationals find Highfly streams |
| Catalyst suite on GitHub Actions | PRs run tests without the Mac |
| Matchday and Search cards use the one-action row | Home, Matchday and Search rows match |

## Month 3: premium moments

| Work | Done when |
| --- | --- |
| Kickoff alert for followed teams that opens straight into Watch | One tap from notification to picture |
| Live Activity with the score while watching something else | Shows on Lock Screen and Dynamic Island |
| Match page as the single home for score, line-ups and Watch | Match page replaces scattered details |

## Stop doing

Chasing new sources or sports before Watch is measurably reliable; long
receipts for small changes; features that don't serve watching.
