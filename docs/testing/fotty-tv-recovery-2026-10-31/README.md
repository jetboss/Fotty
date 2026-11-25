# Sky Sports Football and TV retry repair — 1 November 2026

Normal private 2.0.1 (210) is installed on Jet iPad. Phone, FPL, multi-stream, source opt-ins, backend and TestFlight are unchanged.

## What failed and what changed

| Confirmed defect | Repair |
| --- | --- |
| Original TV11 Sky feed currently carries HEVC in MPEG-TS; Apple exposes audio but no video. Direct and actual-relay Apple diagnostics both decode zero frames, while a TNT2 control works. | Add the exact UK Sky Sports Football NETWORKS entry from the already enabled CS adapter. Fresh catalog/meta/stream identity checks and existing transport guards remain. CS1 supplies compatible AVC/HLS, keeps its label and is preferred on a cold tie. TV11 remains separately selectable. |
| A successful TNT station on the shared CDN made the unplayable Sky station look proven and released its first choice before CS arrived. | Single-stream TV startup evidence is now station/host scoped. Legacy ranking for other playback contexts remains unchanged. No historical success is rewritten into a failure or source ban. |
| Reviewed TV could not use the existing once-only descriptor refresh when repeated actual relay observations established a frozen live window. | Include reviewed TV in that selected-source recovery with the same decoded/foreground/play-intent/owner/current-binding/budget restrictions. |
| Late native fatal callbacks could restart an already terminal single-player attempt. | Ignore those callbacks after terminal failure. Explicit Retry/reselection still creates a new attempt. |

## Verification

- 331 focused tests pass, including exact UK identity, conflict rejection, opt-out, stale binding, cold selection, shared-CDN isolation, frozen-window renewal, terminal callback and relay regressions.
- Signed iOS Release, app/widget210 and deep strict signature checks pass. Final executable hash is in `install.json`.
- First candidate retained separately: TV11 Watch failed; choosing the actual CS1 option then showed the Sky Sports Football watermark and advancing Bradford–Swansea archive footage for124.9seconds without Retry. This exposed the cold-selection gap; it was corrected before the final install.
- Final candidate: ordinary Watch automatically selected CS1. Advancing station picture observed for96.9seconds before controls, with no Retry/source selection. Source sheet confirms CS1 selected and TV11 retained. Native fullscreen exposed Play after Pause, resumed picture advanced, and normal close/reopen played the station again.
- TNT Sports2 started through ordinary Watch without Retry and sustained116.3seconds of observed advancing picture, progressing Moto3 lap6 to lap7. This was on the preceding210 candidate with the same descriptor-recovery and terminal-callback implementation; the final additional change scopes positive station evidence and cold ranking.
-43 protected FPL/multi source files and protected device preferences/source opt-ins are unchanged. Test-created TV recents are cleared to the empty baseline after acceptance.

## Limits

This proves the current channel delivery, not a live Premier League/Champions League fixture, an independent schedule assignment or perpetual supplier availability. The on-air Sky programme was archive football. Audio is not relayed by Device Hub, so no listening claim is made. Frozen-window automatic renewal is exercised by controlled tests; no natural frozen-window recovery occurred during the accepted physical holds. PiP, Watch Two and unrelated screens were not retested. Original TV11 packaging remains incompatible until its publisher changes it; normal Sky Watch uses the compatible alternate while CS remains enabled.

Redacted receipts distinguish metadata/media diagnostics, first-candidate failures and actual normal-app acceptance. Raw media URLs, tokens, device identifiers, build products and owned keep-awake output are removed after the gate.

Apple's [HLS authoring specification](https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html) requires fragmented MP4 for HEVC (requirement1.5).
