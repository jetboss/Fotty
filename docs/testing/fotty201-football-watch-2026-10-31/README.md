# Football Watch repair — 31 October 2026

Owner priority: football only, Premier League first, Champions League next. Jet iPad only; no phone, FPL, multi-stream or TestFlight changes. Cricket physical acceptance remains deferred.

## Confirmed defects and repairs

1. A temporary official-feed collection failure revoked otherwise accepted fixture identities. Protected PR110 retains verified identities for at most30minutes for typed temporary transport failures, with original timestamps and status unchanged. It never overrides conflicts/holds or manufactures LIVE.
2. Official long club names and cross-competition canonical IDs failed exact broadcast joins. Protected PR111 fixes literal aliases/canonical identities without league membership changes. Paris FC/PSG and squad distinctions remain separate.
3. Native fixture identity freshness used the publisher's last *status change*. A freshly fetched PL fixture whose status had not changed overnight consequently rejected fresh broadcast links.199 separates successful identity-fetch observation from status observation. Existing strict LIVE/terminal freshness remains unchanged.
4. A fast HTML result mounted the player before independent direct deliveries arrived.200/201 briefly collect initial unproven choices (at most6seconds, within the existing18second discovery deadline). A proven direct choice or all lanes completing releases immediately. Alternatives remain append-only after the first snapshot; playing/paused transport is not silently replaced.
5. Attempt-family rotation put an untried slow HTML source ahead of remaining direct alternatives.201 initially gave positive decoded-start history priority, but actual testing exposed the host/family evidence applying to every sibling despite this attempt’s failures.202 gives an untried historically positive family its first turn, then rotates across remaining direct alternatives before unknown web fallbacks; current failures override coarse past success for sibling ordering. All source choices remain available. An independent focused review also caught the initial timer starting on diagnostics before any candidate; the timer now starts only with a candidate and has a regression.

## Deployed backend

PR110 and111 merged through protected checks. Current main b91812f/source2026-10-31.broadcast-matching-1 is deployed as matching playback/watchdog versions. All21/3bindings, activation and129notices preserved; actual later collector completion verified. See paired-deployment.json.

PR111 also implements the owner's separately approved, typed limited-overs early-coverage relation (ODI/T20, >15 to60minutes early, sameUTCdate, exact teams/format, unique accepted fixture, fresh same-ID metadata). It does not widen the ordinary football15minute rule or accept late clocks/Test/T10/ambiguity. Cricket physical acceptance is still pending, not passed.

## Physical evidence and limits

199 normal Home Watch reached CS5 for Manchester City–Brighton automatically. Correct live programme advanced from18:51 to25:23 over393seconds. Startup was101.5seconds: playback success, performance failure.200 reached a direct source first in2.53seconds but exposed the web failover ordering defect. Its later decoded clock alone is not programme/90second acceptance. Preserve both runs as failures of the intended fast journey; see physical-before201.json.

201 normal Home Watch again reached the correct CS2 programme and native fullscreen/pause/resume; the source sheet opened/closed while video continued. Its positive-host ordering still drained failedFSsiblings before reachingCS2, so startup performance failed again.202 repairs that observed issue,49focusedtests pass, signed Release verified; 202installed/launchedJet; actualnormalHomeWatch recoveredtoCS2before draining remainingFSsiblings and heldcorrectprogramme>121seconds. Firstrecordedattempt→decoded33.87seconds still misses fast-start intent; host/device tapclocks are uncalibrated.201actualPiP overHome113.056seconds and systemRestore passed; same recorded attempt, player/item objects uninstrumented. UCL current-code support remains, but no live UCL match has been qualified in this gate. Never call all advertised sources working or arbitrary matches guaranteed.

## AS compatibility evidence

At15:48:47UTC AS1.9.130's exact football catalog returned29Roxie rows, including Manchester City–Brighton and Bournemouth–Leeds. Earlier15:22 same-route response had one row and omitted those target names; the earlier row title was not retained.

Same advertised ManCity meta at15:49:52UTC repeats teams/date but only a wall clock marked “site time”. It supplies no UTC/zone/original-source linkage. Its descriptor at15:50:48UTC supplies one HTTPS delivery on a different host from the existing reviewed papacito.cfd contract. Public configure and its linked homepage did not establish the missing timezone/original authority. AS remains enabled; this is unsupported current provider output, not proof AS has no stream. No fixed offset, arbitrary host allowance or playback success was invented. Both date authority and delivery compatibility need verified source-local review before activation.

## Verification

Backend472/watchdog186 passing; native checkpoints and explicit skips are in local-checks.json.201 final discovery/order gate:48tests pass,0fail/skip;202 current-attempt regression gate49pass,0fail/skip. Earlier ownership/retry/health gate212pass. Native tests are local Catalyst tests, not UI testing of the obsolete installed Mac app. Signed iPad Release and final physical results are recorded separately when observed.

## Catalog refresh observation

First201 launch retained an older unavailablePL lane and temporarily lacked Watch. Fresh public metadata independently contained currentPL fixtures; the exact current native validation/acceptance functions admitted that captured payload. Normal manual refresh did not visibly recover during the observed window. A later fresh app launch did restore current fixtures/Watch. No decoder/admission defect or transport cause was proven, so none was invented or patched. This remains an unresolved refresh-observability/recovery gate.

## Final private baseline

Signed202 is installed onJet and left playing the verified PL match.49latestfocusedtests pass; FPL’s6privatevalues,43FPL/multisourcehashes andsourcechoices unchanged.201nativefullscreen/pause/resume/source-sheet/PiP overHome113.056s/systemRestore passed on unchanged presentation code; these controls were not repeated unnecessarily on202. Actual202correctprogramme advanced>121s, automaticCS2 recovery bypassed remainingFSsiblings. AS compatibility, intermittent catalog-refresh cause, liveUCL and deferredcricket remain open. This task is not complete overall and is not TestFlight-ready qualification.
