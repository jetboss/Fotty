# Jet336 focused Watch acceptance

15 November 2026, normal signed private Release 3.0.0 (336), Jet iPad only.
[Installation](jet336-install.json) verified the installed version and strict code
signature. No test launch arguments, source toggles or settings changes.

## Observed outcome

| Normal user action | Actual evidence | Scope |
| --- | --- | --- |
| Home → Sky Sports Premier League → Watch | TV25 recorded first decoded picture in 6.443 seconds; visually confirmed Sky Sports Premier League watermark and football highlights | Channel playback, not a live fixture qualification |
| Unplanned source stall | Attempt 1 stalled. Existing recovery automatically started attempt 2 on the same delivery, reaching decoded video 4.766 seconds after retry start / 4.819 seconds after recorded failure | Real recovery observed; not an independent-provider backup, and the original interval was not uninterrupted |
| Recovered stream hold | 92.580 seconds elapsed / 92.541 seconds media advance, zero recorded stalls in that interval, 1280×720 | Native same-player/item/attempt continuity instrumentation plus visible moving picture |
| Sources | Opened and closed the source sheet while playback continued | Responsive controls, not selection of another delivery |
| Pause → Play | Pause visibly held; resume recorded on attempt 2 without replacement. Afterwards, another 94.037-second interval advanced 94.038 seconds with zero stalls | Same-attempt resume; no restart observed |
| Close → Home → match details → Home | Normal close completed; upcoming Spain–England details opened and closed | No freeze or watchdog termination during this gate |

[Allowlisted runtime evidence](jet336-diagnostics.json) preserves the first stall
and the two later successful intervals. The initial sample was Aston Villa–Man
City highlights, and later Arsenal–Everton highlights. These programmes belong
to the continuously tuned channel; neither is represented as a live match pass.
Device Hub does not relay sound, so audible commentary is unverified. An AirPods
battery panel appeared after resume; it was dismissed without changing audio
settings, and the channel picture had continued advancing.

At the match-card check, Spain–England remained upcoming, scheduled for 19:45
UTC and showing no listed broadcast. No Watch was offered in the normal details
sheet at 19:18 UTC. The earlier Belarus/Suriname/Finland fixtures had finished.
No fixture was relabelled or a channel passed off as a match. Consequently,
**a fresh Highfly match-card playback on 336 remains unverified**. The crash
mechanism and discovery edge cases are covered by the exact-source regression
suite, while this physical gate proves the shared player/recovery/control path.

## Preserved boundaries

[Seven checked preferences and saved-match identity](preservation.json) are
preserved. Only the saved cricket fixture's routine observation timestamp changed;
owner save identity and saved-at values did not. Runtime health/history naturally
changed from actual viewing. Ranking formulas and ordering remain unchanged.
No phone, FPL, Watch Two, cloud, publication or TestFlight work was performed.
Jet is left on responsive normal Home with playback closed.

## Remaining evidence limits

- Baseline HF2's wrong basketball programme under Belarus–Albania is unresolved,
  not fixed by discovery classification or the persistence repair.
- No new Suriname stream supply was established. The recorded missing/conflicting
  listing remains distinct from a failed unread catalog.
- Fresh account-based match playback, audible audio and independent backup
  remain unverified in this gate. No repeat fullscreen/PiP qualification was
  needed for these unchanged presentation paths.
