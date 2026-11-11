# DAZN → Fotty: core experience comparison

Reviewed 29 October 2026. This is a read-only study. No Fotty implementation,
device, account, source setting, deployment or release was changed. Fantasy/FPL
and multi-stream are excluded.

## What was actually inspected

Three current unauthenticated GB web responses: Home, a real event link obtained
from Home, and the linked Schedule. Their complete 2,090,897 HTML bytes were
hashed and parsed inertly; identity and limits are retained in
[public-response-evidence.json](public-response-evidence.json).

The served Home groups current/upcoming events, channels, competitions and
replays/highlights separately. The event link supplies event context and an
explicit signup action. Schedule markup provides calendar date structure.
These are observations of external responses, not native screenshots or
executed interactions. A collection's label is not proof an event is live.

Those initial responses expose no external executable JavaScript and only
JSON-LD inline. No artificial JavaScript application was created from that
metadata. A later actual browser observation by root loaded the public TT
catalogue and exposed three real first-party client chunks. Their exact URLs,
received times, sizes and SHA-256 digests are in [client-assets.json](client-assets.json).
No installed named Mac DAZN artifact was present at the bounded check. Native
player, signed-in personalisation, real playback and runtime accessibility remain
unknown in this sub-study.

## Actual shipped-client REA follow-up

Only those three browser-observed public catalogue chunks were acquired:
882,030 bytes total, filename revision `8880f74`. REA inertly parsed all three,
197,977 AST nodes and 273 recovered modules with zero parse errors. The app and
semantic graphs remain **partial** because result-capacity limits were reached;
this is not a complete reconstruction or runtime analysis. See
[rea-static-evidence.json](rea-static-evidence.json) for exact Evidence IDs, hashes,
limits and a focused asset/module view.

The selected compiled component (module1680 in the `main-325…` chunk) supplies two
useful, bounded observations:

- Its main action is conditional on a separately computed tile-tier availability
  predicate. This is static evidence that content details and an action-eligibility
  decision are separate concerns. External hooks/defaults remain unresolved; this
  does not prove a user entitlement or successful playback.
- Its reminder branch requires an upcoming event plus feature/state conditions.
  The reminder callback suppresses the parent click and carries the current event
  and active-reminder state. The lesson is contextual secondary actions that do
  not accidentally activate the main match action. No click was executed here.

These observations corroborate narrow catalogue interaction mechanisms. They do
not establish native iOS equivalents, paid player behaviour, DRM, latency,
reliability, accessibility or complete feature reachability. The quality/Pulse
features below remain documented evidence, not findings from these chunks.

## Journey comparison

| Journey | DAZN evidence | Fotty baseline and implication |
| --- | --- | --- |
| Choose something now | Actual GB Home markup separates events, channel collections, competitions and past-content collections. | Fotty already has sports/interests and live/upcoming groups. Preserve these; improve the consistency of event-versus-channel identity and actionable availability. Do not add 20 editorial rails to a small private app. |
| Understand whether it can be watched | Actual sampled event response gives context then signup; official Schedule guide documents explicit live, entitlement and purchase states. | A tracked official fixture is different from an available stream. Keep the schedule useful while the action accurately reflects whether playback can be attempted. A successful source-list request is not decoded-video proof. |
| Plan ahead | Actual Schedule response has date structure; official help describes upcoming events and opt-in reminders. | Saved Matchday/countdowns/reminders exist. Refine them rather than adding another calendar destination. Schedule-change/cancellation delivery while the app is closed is a separate real opportunity. |
| Follow favourites and find context | Official Scores help describes team/competition search, variable per-event stats, and contextual links to viewing where available. | Existing follows/search should connect naturally to useful sport-specific event context. The current active Fotty score policy is PL-only; cricket records lack innings/overs/runs/wickets. Obtain verified data before adding score chrome. |
| Watch comfortably | Official mobile help documents device-local cellular/Wi-Fi data saving. Official playback help documents controls, with region/linear-channel exceptions. | Auto/Data Saver/Best where a source supports variants is a concrete addition. Keep native controls and explicit source switching. Do not invent resolution choices for a fixed-quality source. |
| Browse then return | Documented Pulse can return the viewer to the prior feed after an explicitly chosen event switch. | Fotty already retains a live session and a minimized player. Preserve that ownership through browsing/menus; a fresh-resolved last-still-live match card after cold launch is a distinct opportunity. Never persist a stale stream URL. |
| Avoid spoilers | Documented Pulse suppresses alerts for the game currently being watched and limits what an alert reveals. Availability/device scope varies. | Fotty already has spoiler protection. Treat notifications and scores as one preference and ensure a delayed stream is not spoiled by its own live alert. No automatic game switching or new alert flood is recommended. |
| Recover or ask for help | Official help separates unavailable-content, network and playback categories, but many documented steps remain generic restart/update advice. | Existing contextual diagnostics/reporting can be a Fotty advantage. Explain the observed failure stage and offer the relevant alternative; do not blame Wi-Fi for a source failure or make reinstalling the first response. |

## Five transferable improvements, in useful order

1. **One event identity with an honest viewing action.** Event details, the list
   card and player must agree on teams, competition, time and availability.
   Channels remain channels. Where no delivery exists, keep the fixture useful
   without a misleading playback promise.
2. **A clear way back.** Keep the current event, selected source and pause intent
   while viewing context or sources. On a later app launch, offer the last match
   only if it is still current, then obtain a fresh delivery.
3. **Practical device-local quality choices.** Expose a small data/quality choice
   when adaptive variants exist. Measure startup, stalls and data use before
   claiming benefit. Do not copy DAZN's published data estimate as a Fotty fact.
4. **Useful verified match context.** Begin with accurate UCL and cricket state,
   not a generic statistics page. Account for differing data depth and unavailable
   score details rather than substituting misleading empty values.
5. **Short, contextual recovery.** Give a precise user action and a compact report
   carrying the already-known match/source/failure stage with optional reviewed
   diagnostics. Existing reporting should become simpler, not duplicated.

These are product recommendations, not newly demonstrated Fotty runtime defects.
The current Fotty reference is source/build184 and dated prior physical receipts;
184's final live fullscreen/PiP round trip remains deferred by owner instruction.

## What not to copy

- DAZN's large promotional catalogue, betting, shopping, social profile and chat
  surfaces would compete with Fotty's immediate watch task.
- Do not promise DAZN-style catch-up, replay, key-moment clips or rewind when the
  selected feed does not provide a usable DVR window or replay asset.
- Pulse's event-switching behaviour is not a reason to interrupt the owner or
  add automatic switches. Its transferable lesson is controlled transition and
  return continuity.
- Do not assume a GB web response or Japan/Belgium help page proves global native
  availability. Official help itself records country, device and content limits.
- No speed, reliability, buffering, accessibility or native-layout superiority
  has been measured here.

## Primary sources and evidence limits

- [DAZN GB Home](https://www.dazn.com/en-GB/home): actual external response;
  hash/size in the evidence JSON. No signed-in or native behaviour inference.
- [DAZN GB Schedule](https://www.dazn.com/en-GB/schedule): actual external response;
  calendar interaction and fixture accuracy untested.
- [Navigating the DAZN Content Schedule](https://www.dazn.com/en-GB/help/articles/16176654360733-navigating-the-dazn-content-schedule): documented schedule, reminders and entitlement labels; not runtime verification.
- [How to use DAZN Scores](https://www.dazn.com/en-BE/help/articles/19180639607069-how-to-use-dazn-scores): documented football stats/search and viewing distinction, explicitly region/data dependent.
- [Mobile data control](https://www.dazn.com/en-JP/help/articles/16296576543517-how-can-i-control-how-much-data-dazn-uses): documented per-device network choices; UI and traffic not exercised.
- [Pulse](https://www.dazn.com/de-de/help/articles/16296336761501-pulse): documented alerts, explicit switch/return and spoiler behaviour; native availability not established.
- [Pause/rewind help, Spanish locale](https://www.dazn.com/es-ES/help/articles/16294885174045-como-pausar-y-retroceder-transmisiones-en-directo): documents linear-channel exceptions. Other translated help is less explicit; do not generalise DVR support.
- [Streaming troubleshooting](https://www.dazn.com/en-GB/help/articles/16921391054621-troubleshooting-streaming-issues-on-dazn): documented user support only; not proof of failure attribution or internal recovery design.
- [DAZN App Store listing](https://apps.apple.com/us/app/dazn-stream-live-sports/id1129523589?platform=ipad): public native product listing. It is not an inspected binary or exercised native journey.

## Unresolved questions

Authenticated following/search, native phone/iPad layout, startup latency,
retained playback through fullscreen/PiP, selected-source persistence, transport
recovery, subtitle/audio track switching, VoiceOver/Dynamic Type and measured
performance were not observed. The public catalogue and documentation cannot
answer these questions by themselves.
