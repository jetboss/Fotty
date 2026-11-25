# Core viewing priorities

Owner direction, 4 November 2026. The reliability target is Premier League,
UEFA Champions League and every cricket match carried by Willow or Fox Cricket.
Other sports remain available; new bonus-sport work does not take precedence.
Jet iPad is the testing target. Leave the phone, FPL and multi-stream unchanged.
No TestFlight release is authorized.

## What this changes

- Cricket scope includes domestic, women's, international and other competitions
  actually carried by either named station. Existing CPL/West Indies/ICC feeds
  are a subset, not evidence of complete coverage.
- Use broadcaster programme evidence to discover coverage gaps, then corroborate
  teams, competition, date, format and status with the official competition
  source. Replays, highlights, previews and delayed coverage remain distinct
  from a currently live fixture.
- Retain every enabled eligible TV/CS/AS delivery. Rank by current same-match
  reliability and measured startup, not a blanket preference for TV or CS.
  Startup duration is not a measurement of distance behind live.
- Routine collection belongs to the existing cloud collectors. This priority
  does not introduce a Mac-dependent monitoring task or increase request limits.

## Current evidence and remaining gaps

| Area | Verified evidence | Remaining work |
| --- | --- | --- |
| PL / Champions League | Collector retrieval hints already rank these competitions before cricket and bonus sports (`broadcast-source-adapters.mjs`, `retrievalHints`). | Confirm current fixture-to-delivery completeness and normal Watch/recovery on fresh eligible matches; priority ordering alone is not delivery proof. |
| Cricket fixture coverage | `Cricket-Fixture-Service.md` defines CPL and the ICC international feed, with West Indies ownership. | Reconcile Willow/Fox's actual programme schedules with official competitions; add reviewed missing competition coverage through the existing registry, not fabricated fixtures. |
| Willow | 235 suppresses unsupported current-programme claims. TV1 actual Willow replay picture starts5.94s and holds92s; PR122/123 WBBL fixtures reach production and Jet cache. | Verify the current guide/edition join through live match-card Watch. Match9 on4November is finished; replay/channel holds cannot replace that gate. |
| Fox Cricket | 234 shows actual Fox501HD women’s cricket,CS1 holds93s; natural stall recovers toCS3 in17.13s and holds92s. Historical215 subscription-card failure remains separately recorded. | Obtain a current authoritative programme join and prove live match-card Watch. Two CS routes are not proven independent upstreams. |
| Current-event CS | Build234 repairs metadata leases, independent registry clocks and cold-preflight withdrawal; Home Watch resolves UAE–Oman CS1. | Child HLS403 was reproduced outside Fotty. No decoded hold or eligible backup passed for that delivery; investigate only changed provider evidence, not repeated identical retries. |

Evidence: [233](fotty233-neutral-selection/README.md),
[234](fotty234-cs-metadata/README.md),
[Fox programme observation](fotty-cricket-matching-2026-11-01/fox-215-hd-programme-observation.json).
Official WBBL reference:
https://www.cricket.com.au/matches/series/CA:4687/weber-women-s-big-bash-league
(reviewed 4 November 2026; reverify status for any physical test).

## Execution and acceptance

1. Establish coverage completeness against the named broadcasters and official
   PL/UEFA schedules. Track missing fixtures separately from missing programmes,
   failed discovery and failed media delivery; repair the first broken boundary.
2. Fix guide/edition and fixture association gaps. A generic Willow or Fox
   channel does not establish which game is playing. Preserve current identity,
   time, squad, format and transport checks unless verified source evidence
   supports a focused correction.
3. Qualify admitted deliveries through normal match-card Watch on Jet: visible
   tap feedback, measured time to correct picture, 90 seconds of advancing native
   video and working basic controls. Do not substitute a direct-URL test or a
   generic channel tune for the match path.
4. Where two eligible independent deliveries exist, force the primary failure
   and observe automatic same-programme recovery, measuring interruption and
   holding the replacement for 90 seconds. Two labels or routes from one upstream
   do not prove independence. Record a missing backup as an unresolved gap.
5. Keep a per-competition outcome with actual provider/edition and event date.
   Do not call PL, UCL or cricket complete based on another sport's test. Preserve
   previous failures. Reuse controls/PiP regression evidence when the changed
   code does not affect those paths; avoid unrelated repeated device tests.

Work on what can be verified in a current event window without inventing LIVE
status from kickoff or waiting on distant matches while current priority gaps
are actionable. New official-source contracts require review and tests before
activation; deployment remains separately scoped. This document records target
coverage and open work, not an implementation or release pass.
