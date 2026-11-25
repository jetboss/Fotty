# Five-product experience study and Fotty improvement proposal

29 October 2026. **Research and proposals only; no Fotty implementation changes.**
Scope: ESPN, DAZN, Apple TV, JioHotstar and Stremio across discovery, planning,
event context, single playback, returning, recovery, settings and accessibility.
FPL/fantasy and multi-stream were excluded. No device operation, app build,
installation, account/signup, subscription, media qualification, source activation,
Git/cloud publication or TestFlight release occurred.

## Product conclusion

Fotty already has much of the structural foundation: interests, follows, saved
Matchday, Search, visible Save, reminders, native fullscreen/PiP, a retained player,
source groups/descriptions, task-grouped Settings and contextual reporting.
Rebuilding those again would misidentify the problem.

The highest-value jump is to connect that foundation into one dependable sports
journey, then add four genuinely missing services: a last-still-live return after
relaunch, broader next-fixture search, sport-appropriate score context and practical
quality/data choice. Updating changed schedules while the app is closed is another
useful service, but has larger notification/data/privacy requirements.

## What was actually studied

| Product | Fresh evidence | Important boundary |
| --- | --- | --- |
| [ESPN](espn/README.md) | Public delivered markup, current official app/support pages; REA on455,874-byte shipped Web bundle and exact92-byte follow-eligibility fragment. | Whole-bundle semantics partial at bounded heap; fragment globals unknown. Watch access/verification barrier; no paid/native player, latency or PiP observation. |
| [DAZN](dazn/README.md) | Three actual public GB HTML responses; root observed Home→Schedule in the actual TT web session; REA on882,030 bytes of three browser-advertised catalogue chunks, revision8880f74. Focused upcoming-reminder/tier-action logic. | No paid/native playback. Partial graph due result budget; static action eligibility is not decoding proof. Region-specific documentation does not imply worldwide feature parity. |
| [Apple TV](apple/README.md) | Actual public Web MLS hub/event visual and AX review; REA on2,065,834-byte deployed Web bundle plus988 exact focused bytes; primary native product guidance. | Whole-bundle semantics partial; focused external owners unknown. Current Web UI is not the native iPhone/iPad app. No paid/native viewing/control/continuity test. |
| [JioHotstar](jiohotstar/README.md) | Actual official territory-unavailable HTML, current26.10.12 App Store listing/published images and official cricket/product documents. | No executable consumer artifact was exposed, so **no JioHotstar REA/native playback pass** is claimed. No region or challenge bypass. This row is documented-product comparison with a verified access limit. |
| [Stremio](stremio/README.md) | Actual current Web Board→public-domain title/details/source-label journey; REA on exact8,298-byte streams component from the10,270,860-byte advertised Web asset. Official Apple2.1 notes; retained older2.0.7 artifact inventory. | Selected component static only; imports/runtime unknown. Current Web, documented Apple2.1 and old2.0.7 are separate identities. No add-on/service install or media playback. |

This is a completed accessible-evidence comparison, **not a claim to have exercised
five paid native apps end to end**. Locked native playback, live correctness,
provider independence, comparative speed/stability, real VoiceOver/Dynamic Type
and cross-device behavior remain unverified for the competitors. Those unanswered
questions cannot be solved by a bigger static graph or an App Store feature list.

Fotty's baseline is [current source plus dated receipts](fotty-baseline.md), not a
new device review. Jet184 is installed without launch; phone177 remains untouched.
The184 live fullscreen/PiP round trip is still owner-deferred. Test counts from
different gates do not establish full-app acceptance or competitor superiority.

## The useful lesson from each product

| Reference | What to transfer | What to avoid |
| --- | --- | --- |
| ESPN | Treat the match as the stable destination across discovery, search, preferences and viewing. Make sports information lead to a useful action. | Copying promotional/news density, AI branding or adding another destination for an existing task. |
| DAZN | Distinguish events, channels and past content; make the available action reflect event state and access. Offer supported data controls and controlled return to viewing. | Assuming listed content is playable, interrupting viewing automatically, or promising DVR/replays absent from the source. |
| Apple TV | Make team identity and the next useful action clear; connect followed teams, planning and returning. Retain familiar native media behavior. | Decorating every card with glass, oversized promotional heroes, or copying a browsing composition into the active player. |
| JioHotstar | Give cricket its actual innings/overs/score context and support meaningful quality/audio options when supplied. | Cropping an ordinary feed to imitate a producer's portrait broadcast; adding reward games, entertainment clutter or unsupported tracks/4K. |
| Stremio | Keep provider groups independent, show ready choices while others load and preserve sensible selection/navigation state. | Arbitrary add-on trust, external-player dependence, film-ID fallbacks for sports or placeholders that never distinguish finished-empty. |

The larger services' media/catalogue control and supplied replay/data assets differ
from Fotty's third-party-source model. Their interface patterns do not supply a
missing stream. Fotty still needs reviewed fixture identity, fresh source evidence
and actual delivery qualification; no design can guarantee every outside source.

## Complete journey comparison: what changes are worth making

Labels: **new** means a source-confirmed capability gap; **refine** means improve an
existing feature; **verify** means implementation exists but actual acceptance is
open. These are product priorities, not all newly confirmed runtime bugs.

| Area | Fotty today | Proposed tangible outcome | Type / priority |
| --- | --- | --- | --- |
| First minute | Optional team onboarding, sports/league interests and setup tips exist across entry points. | One short, skippable preference journey that previews the resulting Home and clearly explains following a team versus saving one fixture. | Refine / high |
| Home | Ranked live/upcoming groups and interest scopes exist. | The same match state/action across all appearances; one small valid return-to-live card, followed by relevant live and upcoming matches and clear broader-sport access. Keep badges and sport art. | Refine + new return / high |
| Search | Recent queries and followed-entity shortcuts search the already-loaded lineup. | Searching a team outside that lineup still reaches its next known fixture or truthful coverage state, with clear scope. Reuse the reviewed schedule registry and source limits. | New broader schedule lookup / high |
| Matchday | Saved/followed schedule, date groups, countdowns and reminders exist. | Make date navigation and follow/save/reminder distinctions obvious; preserve scroll and current filters on return. Use existing Matchday rather than add a Calendar tab. | Refine / medium |
| Viewing availability | Official fixtures, independent discovery and typed provider states exist; some live qualification and upstream issues remain open. | A fixture card never silently changes meaning across Home/Search/details. Distinguish Scheduled, Checking, Broadcast listed and current playback evidence internally; show concise appropriate user actions. No provider-list success→playback guarantee. | Verify/refine / first gate |
| Match context | Rich football detail exists for admitted data; active live-score policy is PL-only, UCL planned. Cricket fixtures have no runs/wickets/overs/innings. | Verified compact UCL/cricket context with actual sport-specific phase, freshness and unavailable states; useful even without a stream. | New data service / high, dependency gated |
| Sources | Partial results, All/group filter, selected/failed states, listed quality/language and active Native/Web already exist. | Finish late/empty/error/cancellation behavior coherently and preserve selection while browsing sources. Show known properties without converting Listed into measured quality. | Verify/refine / high |
| Single player | Native fullscreen/PiP, video-first iPad, minimize/return and same-session reopen exist. | Preserve those controls/ownership and finish184 physical acceptance. Add a small Auto/Data Saver/Best preference only when variants/qualified deliveries permit it. | Verify + new preference / high |
| Return after relaunch | In-memory retention and explicit Handoff exist; no normal persistent last-live affordance was found. | A removable local event-identity shortcut, freshness-checked before fresh resolution. No saved transport URL, autoplay or implied rewind. | New / high |
| Reminders | Local reminders fire while closed; changed/terminal schedules reconcile when refreshed. | Obtain verified changed/cancelled schedules while closed and update opt-in notifications. No promise of exact push timing or background timers. | New delivery service / later design gate |
| Errors/support | Retry, alternate Sources, Report, prefilled fields and optional reviewed diagnostics already exist. | Faster issue classification such as Wrong match, No sound or Keeps buffering; context-specific action and a short reviewed report. Choose a delivery channel before implementing automatic sending. | Refine / medium |
| Settings/privacy/accessibility | Task groups, appearance, spoiler preference, native semantics and adaptive foundations exist; sync/widget acceptance is open. | Only supported/current choices, readable controls, correct focus and reduced-motion behavior, with useful continuity clearly opt-in. Finish the existing gates; do not add another account/profile system. | Verify/refine / medium |
| Performance | Fotty already records playback stages and has focused responsiveness work. | Compare cold open, search-to-result, Watch-to-first-frame and interruptions in comparable network/device cases. Separate app work from provider delay. No invented competitor speed ranking or expanded telemetry in this review. | Measure / release gate |

## Two corrections to earlier advice

1. **Save is already visible.** Current event ellipsis menus expose Details and
   Save/Remove; setup copy happens to teach long press. The opportunity is clearer
   teaching and consistency, not adding the first visible Save button.
2. **Source metadata and contextual reports already exist.** The picker already
   shows sanitized Listed quality/language and active playback mode. Error-entry
   reports prefill both text fields. Improve known metadata coverage and classified
   reporting instead of counting them as wholly missing features.

Spoiler protection, reminders, native controls, widgets and sports sync code also
exist. Implemented code, owner acceptance and current physical proof remain
different. Current source references for each claim are in the baseline document.

## Proposed phone/iPad experience, before implementation

| Moment | iPhone contract | iPad contract |
| --- | --- | --- |
| Open | Compact return-to-live only when valid; relevant live/next matches; recognisable sport artwork. Preserve normal3-column sport composition and accessibility reflow. | Use the available window for useful live/next groups without uncontrolled full-width text. Support narrow windows; do not design only for full landscape. |
| Find/plan | Team/competition search leads to known next fixtures; Save/Reminder stays discoverable and compact. | Existing date/scope navigation can stay visible while browsing the list. No duplicate calendar or permanently empty side column. |
| Inspect | Badges, exact state/date/competition, one clear primary action and concise verified context. | A match browsing page can show more context, but playback takes priority once started. |
| Watch | Native fullscreen, immediate tap feedback and optional Sources/context. Quality preference is a small supported choice, not another control wall. | Retain the video-first canvas. Details/source tray opens on demand; do not restore the tiny video plus permanent metadata sidebar the owner rejected. Preserve original aspect ratio. |
| Leave/return | Same-session minimized playback retains intent; cold-launch return resolves fresh only after tap. | Fullscreen/PiP/source-sheet transitions retain the same eligible owner; cold-launch shortcut is separate from Handoff. |

These are design acceptance contracts, not new mockups, screenshots or shipped
changes. Preserve the approved Fotty visual direction and team badges. Visual work
must compare exact native size/state/theme/text settings with the agreed reference;
a competitor's Web geometry is not a literal native layout target.

## Recommended implementation order — for owner review

1. **Close the current watchability and native gate.** When separately authorised
   and the device is available, finish184 live decode/fullscreen/PiP and truthful
   source outcomes. Keep upstream empty/wrong-dated deliveries distinct from app
   defects. No player-engine replacement follows from this study.
2. **Improve daily return and discovery.** Add a modest local last-still-live card,
   broader next-fixture search, and simplify existing preference entry points.
   These supply daily value without another tab or external account dependency.
3. **Add useful sport context and viewing choice.** First review a suitable data
   contract for UCL/cricket, then design the compact context. Design supported
   quality/data choice alongside actual variant capabilities and native controls.
4. **Improve planning/support and finish continuity.** Design opt-in changed-time/
   cancellation delivery, shorten the existing report, and close widget/sync/
   accessibility gates. Notification/privacy/backend changes need their own scope.

Before changes, preview the affected phone/iPad flows using real-state contracts
and explicitly labelled sample data. Acceptance should include loading, no current
fixture, no compatible source, late source, replacement/cancellation, finished
event, long names, large text, weak network and returning after app termination.
No artificial source/date/entitlement/security bypass is an acceptable shortcut.

## What this study does not justify

- A wholesale UI/player rewrite, another navigation destination, AI coach/search,
  social feed, betting, marketplace, large promotional carousels or more animation.
- FPL or multi-stream work, which remain excluded.
- Auto-switching games, mandatory accounts, cloud viewing history by default,
  unreviewed sources, arbitrary manifests or new security exceptions.
- Unsupported replays/downloads, Start Over, quality/audio/CC labels or claims
  that a listed stream has been decoded or that a large service never fails.
- Declaring184 TestFlight-ready, operating the owner's devices, publishing code,
  deploying anything or changing source settings under this research request.

## Evidence and completion

The individual product reports retain primary links, exact artifact hashes,
REA Evidence IDs, resource/semantic limits and access barriers. Browser runtime
observations are public navigation/visible states, separate from passive REA.
No personal browser history/account material, private media links or credentials
are retained. Owned temporary artifacts/research tabs are removed at exit.

The final [read-only verification](verification.json) records unchanged app/tool
input hashes, no builds/device/release actions and cleanup. No memory export or
agent-finish regeneration is run for this audit.
