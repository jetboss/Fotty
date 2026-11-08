# Cricket collector → registry → Watch acceptance

Owner scope: repair cricket discovery and CS matching, then test the current live match on Jet iPad. Phone, FPL, multi-stream and TestFlight are excluded. Both Worker publication/deployments explicitly approved on 3 November Tobago time.

## Confirmed failure

ICC returned two terminal Tests beginning 27 and 28 October and ending 31 October. Their explicit intervals overlap the requested 29 October–12 November window. The old kickoff-only filter rejected the complete response, leaving New Zealand–India first ODI (4 November 02:00 UTC) scheduled with an old receipt. Current CS coverage at 01:30 UTC existed but could not link to a fresh official fixture.

## Focused repair

Accept explicitly dated, bounded overlapping Test intervals, retaining original starts and terminal status. Keep malformed/unverifiable source data rejected and prior accepted facts retained. Add finite date/window diagnostic codes. Enforce explicit series-ordinal conflicts for every cricket broadcast kind; missing optional ordinals still do not invent a conflict for a dated event.

The end-to-end regression uses the real collector, state admission, Worker fixture loader, source normalization and registry association. It covers recovery from a stale snapshot, overlapping terminal Tests, valid early coverage, stale official evidence, wrong squads and conflicting ordinals. Existing registry tests cover temporary provider failure without revoking an unexpired listing; no expired media URL is reused.

## Evidence

Protected candidate e593a06 / PR121. 176 focused tests, 186 watchdog tests and both Worker dry-run bundles passed. Fresh production metadata through the protected candidate admitted 71 official fixtures and linked the live first ODI to current CS coverage; the expired CS row remained stale-source. This establishes metadata linkage, not decoded playback.

## Deployment and real Watch result

PR121 merged as `864ca6550459f6d547fa8ab684fa40a6bd986db5`; both Workers deployed as `2026-11-04.cricket-test-overlap-1`. The first production collection at 03:00:35 UTC admitted the live first ODI and its current CS early-coverage link. Activation, bindings, source settings and all 141 watchdog notices were preserved.

Normal installed Jet 3.0.0(230), without rebuild: Watch at 03:02:45 UTC showed immediate discovery feedback and the correct New Zealand–India first ODI picture within 10 seconds. Seven options were visible; CS1 selected. Correct-programme visual samples and native continuity proved 91.006 seconds advancing with zero stalls.

A deliberate pause/resume then exposed a separate failure: CS1 did not resume advancing. After roughly 27 seconds it triggered stall recovery; Willow TV1 advanced 5.555 seconds after automatic failover (about 33 seconds from the resume command). Correct Willow coverage of the same ODI and a further 91.9-second native hold passed. This is a real recovery, not a forced-outage independence proof. Different configured families/editions do not establish upstream publisher independence.

TV1 native fullscreen showed the correct picture and native controls. Pause stayed paused; Play returned a changed picture within seven seconds, with later changed-picture observation. No PiP pass is claimed.

## Remaining issue and evidence limits

CS1 resume failure remains unresolved. Local diagnostics report a moving upstream playlist and no ENDLIST; that does not establish decodable media continuity or identify an upstream fault. The custom resume path publishes Playing before observed progress and uses the general watchdog, whereas the fullscreen path also schedules an eight-second resume validation. This is a code-path difference, not proof it caused the stall. A focused same-delivery comparison of custom/native resume, seekable range, buffer, rate and segment/decode observations is needed before changing the player. Preserve this failed run separately from the successful holds.

No phone, FPL, multi-stream, source-setting or TestFlight changes. No new iPad build. Detailed redacted facts are in acceptance.json and playback-events.json.
