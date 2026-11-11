# Home: watch-first screen contract

Approved by the owner on 10 Nov 2026 as a **concept** (direction only):
[Fotty Home concept](https://claude.ai/artifact/QAvj6NAG5qyfs6cMta3Zy9), private canvas,
boards "iPad Home · landscape" and "One row, one action". The concept uses
sample data: real 10 Nov fixtures, but an invented score, game clock and
source count, team-colour monograms in place of crests, and Inter in place
of SF Pro. Nothing in this contract is implemented yet.

Evidence it replaces: Home on Jet build 261 (9 Nov), before the build 265
stumps/break labels. Re-capture the current build before each slice.

## The screen's job

Answer "what can I watch right now?" first, then "what's coming up?".
Everything else (browsing, planning, details) is secondary.

## Sections, in order

| Section | Shows | When it appears |
| --- | --- | --- |
| Live now | One large card: the best match you can watch now. Followed team first, then confirmed LIVE with a working Watch. Teams, score when covered, status line, one Watch button. | Only when at least one match has a Watch action now. A match at stumps, a break, or "broadcast unconfirmed" never takes this card. |
| On air now | Channels that open now (Willow, Fox Cricket, Sports TV stations, Highfly channels), each with its programme line when known and its own Watch. | Always when a channel can open. Larger, at the top, when nothing is live; smaller, under Live now, when a match is. |
| Today so far | Compact rows for matches paused or over today: Stumps · resumes 1:00 AM, Break, Finished. No action button. | When any exist. |
| Up next | Upcoming rows with sport filter chips and one bell per row. | As now. |
| Browse sports | Sport tiles whose note always says something useful ("3 tonight", "Sat · Premier League", "Off season"). | Tiles with nothing in the visible window move to the end; no "Nothing listed" note. |

## Row anatomy (every Home, Matchday and Search match row)

- Left: both badges (real crest/flag, or team-colour monogram fallback, the same treatment everywhere; never a bare text box next to real flags).
- Middle: team names (two lines on iPad rows), then one status line: competition · status/time.
- Right: exactly one action, or none:
  - **Watch** (gold, filled) when the normal Watch action exists now;
  - **bell** (opt-in reminder, toggles, shows its on state) when upcoming or resuming;
  - nothing when finished or cancelled.
- Details, Save/Remove, Share and source checks move to a tap on the row, the context menu (long-press) and swipe actions. No visible chevron or ⋯ on the row.
- Watch stays beside the team names at ordinary widths; larger text may reflow it below without shrinking names or the 44 × 44 pt target.

## Status words and times

- One vocabulary everywhere: LIVE · In play · Stumps · Break · Resumes 1:00 AM · Starts 8:00 PM · Finished · Postponed.
- Countdown only inside the last hour ("in 19 min"); otherwise the local clock time.
- LIVE still requires the existing confirmed-status rules. A listed start never becomes LIVE.

## Layout

- **iPad landscape:** two columns. Left (flexible): Live now, On air now, Today so far. Right (about 420 pt): Up next, Browse sports. Columns are independent stacks with no forced row alignment, so neither leaves a large empty block.
- **iPad portrait / narrow window:** single column in the same order.
- **Phone:** single column in the same order; keep the approved three-column sports grid at normal text sizes, with fewer columns at accessibility sizes.
- **Navigation:** tabs Home, TV, Matchday, FPL. Settings moves to a gear button beside Search (top trailing). On iPad the tab bar may expand to the standard sidebar.

## Unchanged

Watch admission and source rules, Watch tap feedback timing, player source
switching and PiP, opt-in reminders, badges and sport artwork, dark default
with working light theme, FPL and Watch two behaviour, and the phone FPL
workspace.

## Acceptance (per slice)

Use the design standard's evidence table: Jet, light and dark, default and
an accessibility text size, long team names, a missing badge, mixed sports,
and the states live / nothing live / loading / empty / refresh failed. Labels
stay honest: concept → source checked → automated checked → native visually
inspected → physical interaction checked → owner accepted.

## Build slices

1. **Live now rule.** Spotlight only for a watchable or confirmed-live match; paused/finished go to "Today so far". (`HomeSportsDiscovery.HomeSections`, `SportsDashboardView.homeEntries`.)
2. **On air now.** Bring watchable channels onto Home, reusing the TV tab's station/channel data and Watch path.
3. **One-action rows.** Single trailing action, details and save in tap/menu/swipe, one badge fallback, status words and clock times. (`MatchStartControls`, `HomeDiscoveryRow`, `LiveEventCard`.)
4. **iPad columns and Browse tiles.** Independent left/right stacks; useful tile notes.
5. **Navigation.** Settings to a gear; tabs Home, TV, Matchday, FPL. (`MainTabView`.)

Each slice is its own change with focused tests and a Jet visual check
before the next one starts.

## Slice evidence

| Surface/state | Reference and intended hierarchy | Build/device/window/appearance/text size | Observation and remaining gap |
| --- | --- | --- | --- |
| Home, nothing watchable, cricket at stumps (slice 1) | Live now card only for a watchable match; paused cricket under "Today so far" | Release 3.0.0 (267), Jet iPad Air 4, landscape full screen, light and dark, default text, 10 Nov 16:50 UTC | **Native visually inspected.** No Live now card; Pakistan v Sri Lanka listed under "Today so far" with "Stumps · Play finished for today"; Up next, Browse sports and Later today unchanged. Rows still show the chevron and ⋯ (slice 3); "Football · Nothing listed" tile remains (slice 4). A watchable live match was not on air, so the Live now card itself was not seen on device. |
| Home, On air now with nothing watchable live (slice 2) | Channels that open now, in the TV tab's order, each with Watch; programme only when the guide confirms it | Release 3.0.0 (269), Jet iPad Air 4, landscape, light and dark, default text, 10 Nov 19:49 UTC | **Native visually inspected.** "On air now" leads Home with Willow Cricket, Fox Cricket and TNT Sports 1, each "English" and a Watch button; Today so far, Up next and Browse unchanged. UI-test mode skips the app's guide refresh, so no "Now · programme" line was seen. Home Watch reuses the TV tab's `SportsTVWatchPolicy`; tapping it on the device was not tested in this slice. A paused Test row showed "Finding a broadcast…" in one capture (existing background check; slice 3 row work). |
| Home rows, one action and clock times (slice 3) | One trailing action (bell here); Details and Save in long-press and VoiceOver actions; clock time beyond the last hour; real flags for cricket nations | Release 3.0.0 (271), Jet iPad Air 4, landscape, light and dark, default text, 10 Nov 20:11 UTC | **Native visually inspected.** Up next and Later today rows show only the bell, with no chevron or ⋯; times read "Starts 8:00 PM"; Pakistan and Sri Lanka show flags. The stumps row no longer shows "Finding a broadcast…" but still reads "No stream listed" (a resume-time line is not available yet). Long-press menu and VoiceOver actions were not exercised on device. Matchday and Search cards (`LiveEventCard`) and the Live now card keep their old controls until a follow-up. Montréal Canadiens still uses a monogram because its crest isn't found. |
| Browse sports tiles (slice 4) | No "Nothing listed"; a tile with nothing nearby names its next verified fixture ("Sat · Premier League") or says "No fixtures soon", and stays last | Release 3.0.0 (272), Jet iPad Air 4, landscape, light and dark, default text, 10 Nov 20:29 UTC | **Native visually inspected.** Football tile reads "No fixtures soon" and sits last; Cricket "Play finished today", Hockey "8:00 PM". The next Premier League fixture was not named on device: the verified schedule held no football in the next 14 days at capture time (international break), so the "Sat · Premier League" form is covered by a unit test only. Columns were already independent stacks; no layout change was needed. |
| Navigation: Settings as a gear (slice 5) | Tabs Home, TV, Matchday, FPL; Settings opens as a sheet from a gear beside Search, with Done | Release 3.0.0 (273), Jet iPad Air 4, landscape, dark, default text, 11 Nov 00:15 UTC | **Physical interaction checked.** Tab bar shows Home, TV, Matchday, FPL; the gear opens Settings; Sports continuity pushes inside it; Back then Done returns to Home (`testPhysicalSportsContinuityRemainsOptIn` passed). The same capture showed a real Live now card (Toronto Maple Leafs, LIVE, with Watch), the slice 1 card on device for the first time. Settings is reachable only from Home. |
| Phone pass, all five slices | Same contract on iPhone: single column, Live now, On air now, Today so far, one-action Up next rows, gear and four tabs | Release 3.0.0 (274), iPhone 15 Pro Max, portrait, light and dark, default text, 11 Nov 02:19 UTC | **Physical interaction checked.** 60 s launch hold passed; Home captures passed in both appearances; gear → Settings → Sports continuity → Back → Done passed. Live now showed Toronto Maple Leafs v Colorado Avalanche (LIVE, Watch); On air now Willow Cricket and NBC Sports NOW; two NHL games "In play" with Watch; Pakistan v Sri Lanka under Today so far with flags; Up next "Starts Wed 2:30 AM" with bells. Gaps: the Live now card still has its ⋯ (separate session); women's national sides ("Uganda Women") miss their flags; the stumps row reads "No stream listed"; the Willow 90 s hold is iPad-only and skipped on the phone, so phone playback is not yet proven. |
