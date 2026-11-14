# Private build 323 provider and Watch verification

## What changed

- Discovery and Watch apply the same fixture identity checks to every listing. A disputed provider ID is excluded even when another listing is clean. An independent listing for the right match remains eligible. Flix also checks the competition for each candidate before choosing one.
- Generated source labels and the Watch cache accept the same numbered choices through 100. CNC retains its football teams/date checks and bounded lookup rotation. PenguPlay checks each listing's current metadata and excludes withdrawn or replay-only coverage.
- Plavio collects distinct deliveries across independently matched listings. An empty first listing no longer hides a working second listing. Reviewed TV keeps distinct advertised deliveries for the same station within its reviewed station, destination and header profiles. On stations with alternatives, renewal preserves the selected delivery across reordering. A changed URL that cannot be linked to the selected backup requires fresh selection.
- Owner Status distinguishes entries offered by a provider, distinct choices admitted by Fotty and Watch taps reaching a first picture. Counts summarize retained local lookups on the installed build. They are not a per-match inventory or proof that every candidate decoded the correct programme.

## Automated checks

The combined Catalyst unit and integration run passed 2,641 tests. Twelve opt-in checks for live services, physical decoders or a reference-player soak skipped. The separate approved visual baseline comparison passed. Worker, watchdog and top-level tooling checks passed 755 tests, the remaining web suite passed 46, and Python checks passed 82. No simulator was used. These totals exclude the earlier exploratory and targeted reruns.

The tested native source and project matched the local baseline after the fast-forward merge to `1deda63`. Prior working changes on the baseline were included in the test snapshot. The app and extension were packaged together for one private installation.

## Normal Watch on Jet iPad

Jet reported 3.0.0 (318) before installation and 3.0.0 (323) afterward. Both app and extension versions were checked before the install. Home → Live now → Colombia–Chile → Watch opened HF1. The broadcast scoreboard showed COL 1, CHI 0 at 62:22 and again at 63:00. The contemporaneous [match scoreboard](https://www.espn.com/soccer/match/_/gameId/401921325) also had Colombia ahead 1–0. The app recorded 12,150 ms from Watch to first decoded picture and 8,373 ms from the Highfly source attempt to that picture.

For this tap the local log recorded a Highfly lookup with three entries offered and one admitted. CS recorded two lookups with two offered and zero admitted each. The second count represents a second lookup and can include the same upstream entries. Plavio's catalog request timed out, CNC exhausted its lookup budget, and PenguPlay stopped at programme/channel matching. None of those three produced the picture for this match.


The player’s Sources sheet identified one choice, Broadcast 1 / HF1. The visible scoreboard advanced from 62:22 past 64:28. The native continuity receipt recorded 92,736 ms elapsed, 92,736 ms of media advance and zero stalls. This match supplied one playable choice, so it did not exercise a live backup switch. The tests cover a later numbered choice, an empty first listing, multiple deliveries for one station, reordering on renewal and disputed identities.

## Owner Status on the installed build

Under **Source activity on this build**, the visible rows agreed with Jet’s local records:

| Source | Offered | Admitted | Lookups | Watch taps reaching first picture |
| --- | ---: | ---: | ---: | ---: |
| CommunitySports | 4 | 0 | 2 | 0 |
| Highfly | 3 | 1 | 1 | 1 |
| PenguPlay | 2 | 1 | 1 | 0 |

PenguPlay’s counted lookup occurred at 01:35:03 UTC, after the Colombia watch session. It cannot be attributed to that match. Owner Status showed “Add-on messages” as Highfly’s latest reported rejection and “No link” for PenguPlay. The screen’s 8.4-second median counts time from source attempt to video; the 12.15-second end-to-end figure includes discovery. Playback evidence here is for HF1. Reviewed TV and Plavio’s multi-listing behaviors were verified in the respective deterministic suites.
