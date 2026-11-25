# Apple TV → Fotty — 29 October 2026

Read-only public-web, shipped-artifact and primary-document study. No native Apple
TV app or Fotty device was operated. No subscription, account, playback, watchlist,
follow, notification, source setting or release was changed.

## Actual evidence

- Public `tv.apple.com` HTML advertises `assets/main~Brxe4_UoZn.js`. The actual
  2,065,834-byte bundle has SHA-256
  `2ec7bd510d97f1029f3cc640b14ec444c864e563e01c2aae4244e2b24c3b9b08`.
  This is a deployed web asset, not an iPhone/iPad binary or version identifier.
- REA parsed 686,555 AST nodes, zero parse failures. The 512MiB semantic worker
  reached its bounded heap limit. Whole-application and semantic coverage remain
  partial: [canonical summary](rea-full-summary.json), parent
  `ev_38bc146e306481f32840af2452c5a35374d977c9ca531a5ccf987ff75af7fa92`.
- Three exact, unmodified function/expression slices total 988 bytes, with original
  UTF-8 byte ranges and parent hash in [provenance](apple-fragment-provenance.json).
  Their separate REA analysis parsed 261 AST nodes, zero failures, complete
  application coverage only within these slices, 59 semantic unknowns. Parent
  `ev_52cc7d09af9777bf1450b07e9014f021f892989470a79adfd72e02bc26c51423`;
  [summary](rea-focused-summary.json). Outer bindings and external owners are
  omitted; this is static control-flow evidence, not executed behavior.
- A retained [module view](rea-play-label-module.json), Evidence
  `ev_2605a9a55fab9d20f186fb0f203d152dcdc82836d53eee01ffb19822a8aabb14`,
  authenticates the selected Play-label source module and its exact ranges.
- Normal browser inspection covered the public MLS hub and a publicly linked
  completed San Jose–Colorado event. Actual rendered pixels and accessibility
  text were inspected. No Play/Recap/Full Replay/Add action was activated. No
  personal watch history, account details or avatar imagery is retained here.

## Observations and useful lessons

The sampled event page leads with team identity, final status and venue/context,
then offers distinct Recap and Full Replay actions. The hub has club browsing and
other-content groups. This makes the event's lifecycle and possible next action
explicit. It does not establish playback entitlement or decoded-video success.

The observed web MLS hub also included cards labelled Final under a Live Matches
heading. Treat that as a bounded observation of this page, not a global/native
Apple defect. Fotty should derive section membership and action vocabulary from
verified current status rather than copy an appealing shelf name.

Selected shipped code distinguishes Play, Resume and Play Again using supplied
viewing-state fields. Its resume-label helper uses duration and cursor when those
exist, otherwise a generic resume label. A separate key-play completion function
returns through a pause action when its reduced-motion branch is active; other
branches move to another key play or live edge. External state, action owners and
runtime execution remain unknown. None of this proves native AVPlayer ownership,
PiP continuity, football-score freshness, source availability or startup speed.

Apple's published app description documents Watchlist, Continue Watching and
cross-device return. Its current guide documents following clubs and hiding sports
scores, subject to region/device/content availability. These are documented native
features; the account and native flows were not exercised.

## Full-journey implications for Fotty

| Journey | Fotty should do | Existing foundation / boundary |
| --- | --- | --- |
| Open Home | Make the relevant live or next match the obvious useful action; retain a visible route to broader sports. | Interests and ranked live/upcoming groups already exist. Do not replace them with an entertainment-style promotional carousel. |
| Plan | Keep following a team and saving one fixture separate, comprehensible actions. | Both exist, including visible Save menus; improve consistent teaching rather than build another library. |
| Understand an event | Put badges, exact competition, state and useful sport-specific context before secondary controls. | Match details exist. Cricket context and UCL score activation need actual data, not just layout. |
| Watch | Give video priority, use native controls and disclose useful context on demand. | Video-first iPad/native fullscreen/PiP already exist. Their build184 physical acceptance remains open. |
| Return | Offer one clearable local last-still-live shortcut after relaunch, using fresh status/source resolution. | Same-session retention and Handoff are already implemented. This cold-launch behavior is a distinct new capability; no implied DVR. |
| Choose settings | Show current, supported choices; preserve readable native controls and optional personalization. | Task-grouped Settings, appearance, spoiler protection and accessibility foundations already exist. |
| Recover | Keep event identity and intent stable; explain the relevant source/network/state problem. | Apple static labels do not establish how its internal recovery works; no superiority claim follows. |

## Phone and iPad design direction

For phone, use a compact event header and a clear inline action, with full team
names at accessible text sizes. Upcoming plans and return-to-live should not create
another deep navigation chain. For iPad, preserve the current video-first canvas;
details belong in an explicitly opened companion/sheet. A stadium hero can be
appropriate on a browsing page but must not permanently shrink the playing video.
These are proposed Fotty contracts, not native screenshots or implemented changes.

Do not copy large autoplay promotions, generic glass over every card, a Replay
button without a real replay asset, Start Over without a DVR window, score hiding
as if it were new to Fotty, or reduced-motion declarations as accessibility proof.
The sampled web page's geometry is not the native iPhone/iPad design specification.

## Primary sources

- [Observed public MLS hub](https://tv.apple.com/us/channel/mls/tvs.sbd.7000).
- [Observed event page](https://tv.apple.com/us/sporting-event/san-jose-earthquakes-vs-colorado-rapids/umc.cse.1cvhz4wuujn3v17z4wrq9ytaw).
- [Current Apple TV listing](https://apps.apple.com/us/app/apple-tv/id1174078549):
  published native product/accessibility declarations, not interaction tests.
- [Manage favourite teams and sports scores](https://support.apple.com/guide/tvapp/manage-favorite-teams-sports-scores-atvb30739feb/1.0/web/1.0).
- [Apple video design guidance](https://developer.apple.com/design/human-interface-guidelines/playing-video).

No paid/native playback, comparative latency, long-hold stability, native PiP,
screen-reader interaction, quality switching or cross-device test was performed.
