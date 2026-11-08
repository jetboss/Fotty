# CNC, TENIES, StremVerse and Nebula — 4/5 November 2026

Private Release 3.0.0 (242) installed and launched on Jet. LS1 passed live WBBL acceptance on Jet. Independent backup coverage and full TestFlight readiness remain unverified; see the final live check below.
Owner scope: prioritize genuinely additional football/cricket streams; Jet only. Phone, FPL,
multi-stream, source preferences and TestFlight remain unchanged. No cloud/Git publication.

## Fresh research

| Candidate | Actual evidence | Decision |
| --- | --- | --- |
| CNC PlayZTV WBBL | Exact dated Adelaide Strikers Women–Brisbane Heat Women metadata, 5 November 04:40 UTC, agrees with Cricket Australia. Advertised HTTPS Rutube master and RTBCDN media returned200; one bounded segment decoded Sky Sports Cricket. The picture was a Hobart–Melbourne replay before the scheduled match. AS mirrors this event but returns only Tapmad/FanCode, so this delivery is additional. | Prepare existing CNC/LS adapter path; normal Watch and correct live programme still pending. |
| CNC other unused lanes | PlayZTV Bangladesh–West Indies03:30 UTC agrees with ICC; PlayFy04:00 conflicts. New mydex/itcnbd routes returned403. SKTech Millonarios–América01:30 UTC agrees with DIMAYOR but both advertised HTTPS paths ended403. SportzX sampled cricket paths overlap existing providers or use incompatible transport/DRM. | No speculative timezone repair, HTTP/ClearKey workaround or new playable claim. |
| TENIES.SPACE1.5.0 | Soccer/cricket event catalogs empty at this observation. Sky Cricket and TNT1 return HLS, but their exact delivery paths duplicate existing TV10/TV12. Willow and Fox channel paths returned503. | No duplicate source added; empty event catalogs remain pending,503 is time-scoped failure, not permanent exclusion. |
| TENIES additional channels | Astro Cricket and Sky Sports Premier League return200 HLS and200 media segments. Bounded segment-prefix frames show Cricbuzz-branded New Zealand–India cricket and a Sky Premier League Arsenal–Tottenham2008 replay. These are different channels on the same existing CDN, not independent failover supply. No current match association or normal Fotty acceptance established. | Channel candidates remain pending; not counted as live-match passes or rejected for replaying overnight. |
| StremVerse3.0.0 | Public event catalog lists Bangladesh–West Indies without date evidence. Advertised Tapmad/T-Sports/FanCode endpoints overlap CNC. | No new independently compatible delivery established. |
| Nebula1.3.1 | Free configuration manifest reviewed. Afghanistan–Zimbabwe dated event yields existing FanCode HLS, ClearKey DASH intended for its player, sponsor/external links. Sky Cricket entry yields unlock/donation link. | No compatible genuinely new native delivery; no payment, credentials, challenge or DRM workaround. |

Primary references: [CNC maintainer](https://www.reddit.com/r/nuvioaddons/comments/1wxgy1s/live_sports_and_live_tv_channels_on_nuvio_with/),
[TENIES announcement](https://www.reddit.com/r/nuvioaddons/comments/1xl4y1f/new_addon/),
[StremVerse](https://stremverse1.alwaysdata.net/), [Nebula](https://sports.nebulapro.xyz/sports),
[Cricket Australia match](https://www.cricket.com.au/matches/CA:40630).

## Candidate implementation

CNC PlayZTV WBBL is separate from existing LivXow NHL. Official verified T20 WBBL fixture,
exact women’s teams/date/start and fresh same-ID source metadata are required. Terminal/conflicting
fixtures stay rejected. Catalog matches are verification hints, not decoded-playback or LIVE claims.
Normal Watch/picker/LS labels, existing opt-in, bounded fetches, cancellation and renewal binding are reused.
NHL and cricket catalogs fail independently. HTTPS public-address checks, guarded relay, scoped
advertised header and signature/path checks remain. New route does not inherit NHL timing exceptions.
No media URL, signature, private identifier or signing material belongs in these receipts.

## Checks

- Initial Catalyst execution was blocked before tests by host deployment-target mismatch.
- Same local macOS27.0 override used by the earlier gate:45 focused adapter/matcher tests passed,0skips.
- Signed Release app and widget both242; signature verified, installed once on Jet and launched. Settings visibly showed v3.0.0 (242). Home displayed the correct WBBL match as upcoming with the local 00:40 start. No source/private settings were changed. A working URL or replay picture is not qualification.

The broader integration run initially reported111 passes/1failure: an existing TV-label test still capped the channel list atTV8. Its explicit label contract was updated to current reviewed channels, including rejection of withdrawn/unassigned labels. The initial receipt remains a failure, not rewritten as a pass. The first Release compile was intentionally cancelled before installation to consolidate the reviewed fixture-scope integration.

Final focused adapter/matcher/catalog/optional-source integration suite:112 passed,0failed,0skipped. Native target membership passed. Both stale TV-label test failures are retained in the work log; current expectations cover reviewed labels and explicit withdrawn gaps. Jet baseline source switches were visually allON before installation; none were changed.

## Named live checks

At 03:12 UTC the real PlayZTV catalog was 463,073 bytes, within the existing 512 KiB cap.
[Sky’s broadcaster guide](https://www.skysports.com/watch/cricket-on-sky) lists Adelaide–Brisbane
on Sky Sports Cricket starting04:35 UK time on 5 November; Cricket Australia lists the official
match start at04:40 UTC. This corroborates the scheduled programme, not current playback.
At23:16 Tobago the normal Jet card still correctly showed a future fixture and said the source
listings would be rechecked closer to the start. No attempt was made to force a replay through Watch.

The bounded chat follow-up `fotty-242-live-cricket-source-acceptance` was created ACTIVE for
23:45 Tobago on4November (Bangladesh–West Indies changed-availability check) and00:45 on5November
(Adelaide–Brisbane normal Watch). Inspect the official in-progress evidence, source picker,
correct programme and 90-second advancing picture; keep failed/replay/duplicate evidence separate.
No recurring production monitor and no release. The owner's Mac keep-awake assertion for this
window is PID88613, started 4November23:16:16 Tobago, exact command `/usr/bin/caffeinate -di -t 14400`.
Before stopping, verify PID, command and start time; never terminate unrelated assertions. The
4-hour ceiling is a failsafe if this follow-up cannot run. Initial unbounded assertion was stopped.

**5 November, first live window (03:49 UTC trigger).** ICC reported Bangladesh–West Indies, second Test, day 1, “Play In Progress”; West Indies elected to bat. PlayZTV’s fresh catalog and same-ID metadata agreed on the teams and 03:30 UTC start and named the ICC World Test Championship, but supplied neither a Test ordinal nor a day. Of the two previously checked deliveries, the advertised mydex request timed out within eight seconds; itcnbd was no longer directly advertised. Neither result establishes a decoded stream or a provider-wide outage. No stale link was used, no Test-day or PlayFy timing rule was relaxed, and no iPad playback attempt was warranted. The separate WBBL window remains pending.

**5 November, 00:45 Tobago — final live check, normal Jet Release 242.** Cricket Australia explicitly reported CA:40630 in progress, not completed (WBBL Match 10, Adelaide Strikers Women–Brisbane Heat Women, 04:40 UTC). CNC returned one matching catalog row, the same advertised ID in metadata, exact teams, competition and UTC start. Its reviewed master returned 200 with six variants. Home initially displayed “Broadcast unconfirmed” at 00:41, then offered Watch by 00:45 without changing settings. Time that the button became available between those samples was not measured.

- One Watch tap from the live match card: still buffering at +13.5 s; correct native picture visible by +18.0 s. Normal picker showed LS1 selected, AS1 marked Try again and AS2 available to switch. LS1 showed Sky Sports Cricket, WBBL Match 10 at Drummoyne Oval; Heat batting, Harris and Knott facing Larosa. Observed live action at +18.0, +67.3 and +111.6 s: 0/8 (1.1), 0/9 (1.2), 0/9 (1.4). **LS1 passes the 90-second gate for this match.** Deliberate Pause displayed Paused; Play returned to visibly advancing action after a brief reconnect. Audio was not measured.
- Switching to AS2 produced an automatic source-switch notice by +4.9 s; by +12.9 s the same game was back at 0/10 (1.5). The picker then showed AS2 marked Try again and LS1 selected. This demonstrates recovery *to* LS1 after a real AS startup failure. It does not demonstrate a backup when LS1 is the source that fails.
- Fresh same-ID AS metadata advertised Tapmad and FanCode paths. A bounded Mac probe returned 403 on Tapmad, 404 on one FanCode master, and 200 on the other master but 403 on its first advertised variant without cross-origin headers. These are separate network observations, not proof of the iPad’s specific HTTP error. No expanded header forwarding, route exceptions or repeated challenge attempts. No second independently playing delivery was verified, so no forced LS1 outage.
- Release decision: accept this new WBBL delivery for private testing; hold TestFlight readiness for independent backup proof. No source qualified for the Bangladesh Test in the first window. No new PL/UCL or football acceptance is claimed by this cricket run. No rebuild, install, opt-in change or publication was required.
