# ESPN comparison — 29 October 2026

Read-only research for Fotty's core sports experience. No native device, account,
subscription, media, FPL or multi-stream interaction; no Fotty implementation,
publication or TestFlight action.

**The strongest transferable lesson is a coherent route from a sports event to a
viewing option, with the same preferences and match identity across entry points.**
This review does not establish that ESPN starts streams faster or has better
native recovery than Fotty.

## Evidence actually obtained

- **Shipped public web artifact, not executed:** ESPN's home HTML served build
  `0.799.1.2`/asset version `0.799.1`, fetched at 13:30 UTC. Its directly advertised
  `espn-critical.js` is 455,874 bytes, SHA-256
  `a2266b32fd9e0d23a9e9b2b4c1d6cf3c5318880e7a1dd41602f6f94fdedc955d`.
  Total acquired HTML and JavaScript: 718,745 bytes. Public metadata and hashes
  are in [artifact-inventory.json](artifact-inventory.json).
- **REA whole-bundle analysis:** one source parsed, 114,788 AST nodes, zero parse
  failures. The 384 MiB worker exhausted its heap during semantics; application
  and semantic coverage are partial. No broad absence, execution, storage or
  reachability claim follows. Summary Evidence
  `ev_480901ffda1a8f35f7da21d84bdec6ae8498a2c617284f8d67726c252a4ae6eb`;
  retained parent
  `ev_80151676e34bb60ff9066e8f71b5281d29122d2b38e1130c9e6c826f6778eece`.
- **Focused exact-byte REA:** the unmodified 92-byte assignment at parent byte
  range `[174081,174173)` assigns a follow-card eligibility function using
  anonymous-favorites OR logged-in state. It parsed 21 AST nodes with no failure;
  application coverage is complete only within this fragment. Semantic coverage
  remains unknown with three external-object unknowns. This is a static gate,
  not proof that a user can save, sync or successfully operate favorites.
  [Provenance](fragment-provenance.json); summary Evidence
  `ev_46576606257a02f2ac7abba3d5480b242d1908c4c562f9c144e21f485787cb9a`;
  parent `ev_b4d7007eb0dbea0fa09312352841c19ccef172aa18862753b359bf3cc0b1e480`.
  Both complete inline summary records are retained beside this report.
- **Access boundary:** the Watch route returned HTTP 404 in the inert fetch and
  a JavaScript robot-verification page through the web tool. No challenge was
  bypassed. The app promotion page's direct fetch returned 403; its official
  feature description was available through the web reader. Paid player,
  logged-in personalization and native iPhone/iPad behavior were not inspected.

## Full-journey comparison and proposed improvements

| Journey | ESPN evidence and confidence | Fotty comparison | Proposed product outcome |
| --- | --- | --- | --- |
| Find a game | Public server-delivered navigation contains a dedicated viewing guide entry; ESPN documents a searchable, personalized day-wide guide spanning multiple broadcasters. This is delivered markup plus documented behavior, not a completed runtime journey. | Fotty already separates official fixtures from optional source discovery. Catalog absence must not erase a known fixture or masquerade as confirmed watchability. | Use one match identity across Home, Search, Matchday and the player; make the viewing state/action consistent wherever it appears. Keep scheduled, checking and usable-option evidence distinct. |
| Make it personal | The current bundle's static follow-card gate permits anonymous or logged-in state. The app guide separately documents account-based favorites and alerts. | Fotty already stores team/league/sport preferences locally and offers optional onboarding. Adding another account gate would not deliver this benefit. | Make existing preferences immediately change the same relevant events across Home, Search shortcuts and planning. Preserve optional setup and private local use. |
| Search with intent | ESPN's May 2026 support page documents results that connect game times, scores and viewing links. Its AI implementation and accuracy were not inspected. | `SearchView.swift` deliberately projects Home's already-loaded catalog and already has recent queries and followed-entity shortcuts. | A team with no current listed event should still lead to its known next fixture or a truthful schedule state. Extend reviewed event coverage coherently; an AI search feature is unnecessary for this outcome. |
| Understand a match | The official app guide documents scores, stats and in-game supporting context. No native layout or live data accuracy was verified. | Fotty has match details and a video-first iPad player. Its current core data scope is uneven across sports; do not claim parity from one football scoreboard. | Prioritize accurate UCL and cricket context using reviewed feeds, with sport-specific fields. Keep details optional beside/below video rather than restoring a permanently narrow player. |
| Start and control video | Live viewing, cross-screen controls and availability qualifications are documented; direct paid/native playback is unobserved. | Fotty already has native fullscreen/PiP, source selection and retained-player ownership. Build 184's new physical round trip remains deferred. | Preserve these controls and measure Fotty's actual startup and recovery. ESPN's brand or feature list is not evidence for replacing Fotty's player or weakening source checks. |
| Return later | The examined artifacts do not establish ESPN's cold-launch recent-live behavior. | Same-session retained playback and search history are distinct from persisted viewing history in Fotty. | Consider a removable, local last-still-live match shortcut after independent Fotty inventory confirms the gap. Recheck status and discover a fresh source; do not revive an expired transport or imply DVR. This is a Fotty opportunity, not an ESPN-derived finding. |
| Recover and get help | ESPN support distinguishes a provider/subscription access problem and routes it to that provider or ESPN support. That article is dated July 2020, so current exact UI/error wording remains unknown. | Fotty's `PlaybackErrorOverlay.swift` already exposes retry, alternate sources and a contextual feedback sheet. | Improve the existing report to select a concrete issue and prefill reviewed match/source/stage context. Distinguish no candidate, expired delivery, preparation failure, network interruption and wrong programme without showing raw engineering logs. |
| Accessibility and variation | ESPN documents caption support for selected broadcasts, but the June 2026 article still includes legacy iOS settings paths. Native Dynamic Type, VoiceOver, focus and iPad layouts were not observed. | Fotty's native accessibility and adaptive-layout gates need their own exact-build evidence. | Surface captions/audio only when supplied by the feed and verify focus, readable names, large text and controls in Fotty. Do not treat a competitor support page as accessibility acceptance. |

## What I would transfer first

1. A single consistent event-to-viewing journey, including unambiguous unavailable
   and still-checking states, before increasing the number of sources or screens.
2. Personalization that changes useful content everywhere, with quick optional
   setup and no mandatory account for ordinary local use.
3. Useful, verified match context for Fotty's priority football and cricket users.
4. Actionable search results for the next known fixture, even outside the current
   Home list, while preserving shared timing/identity truth.
5. A shorter existing failure-report flow that carries the user's match context.

I would not reproduce ESPN's promotional density, introduce a news/highlights
production obligation, add AI search solely because ESPN advertises it, or infer
native player performance from static web code. Rights, subscriptions, captions
and regional access qualify ESPN's features; these resources do not supply a new
Fotty stream or authorize content access. FPL and multi-stream remain excluded.

## Primary sources

- [Current ESPN app feature guide](https://plus.espn.com/app): personalization,
  scores, viewing, contextual information, alerts and cross-screen features.
- [Viewing guide announcement](https://espnpressroom.com/press-release/espn-launches-where-to-watch-on-espn-app-espn-com/),
  28 August 2024: event-oriented discovery, favorites, service links and editorial
  data ownership. This is product documentation, not current backend inspection.
- [Search Beta support](https://support.espn.com/hc/en-us/articles/44778820794260-What-is-ESPN-Search-Beta),
  updated 12 May 2026: actionable search spanning viewing and sports information.
- [Provider-access error support](https://support.espn.com/hc/en-us/articles/115003803991-Why-does-an-error-message-display-while-playing-live-streaming-video-on-ESPN-com),
  updated 20 July 2020: documented classification and support escalation only.
- [Caption support](https://support.espn.com/hc/en-us/articles/115003803851-Does-live-streaming-on-the-ESPN-app-offer-Closed-Captioning),
  updated 5 June 2026: selected-content availability; legacy instructions retained.

Source comparison uses the current repository, including `SearchView.swift`,
`PlaybackErrorOverlay.swift` and Current-State. It is not a new physical UI audit.
Native paid flows, actual stream quality, playback speed, long-hold stability,
PiP, accessibility and cross-device continuity remain **unverified for ESPN**.
