# Fotty QA Playbook

Last updated: 2026-10-13

## 2026-10-31 — Verification follows the changed subsystem

Owner explicitly rejected repeating PiP and unrelated player tests after every channel-only build. Verify current playlist identity, declared language, source admission, ordinary Watch selection and sustained native video for changed channels; verify native navigation/layout when moving TV. A build-number increment alone does not require PiP, fullscreen, multi-stream or FPL testing.

Repeat PiP/background/fullscreen acceptance when changing the player, AVKit presentation, session ownership, audio/background lifecycle, relevant OS behavior, or investigating a reported regression. Preserve earlier accepted and failed receipts separately. Broader distribution qualification remains an actual release gate; this private TV update does not authorize TestFlight or phone testing.

## Private142 retained-viewing gate (Jet installed, no shared release)

142 is signed and read back on Jet with sports App Group/KVS capabilities. Home
light/dark, complete Search, Tonight/Full mode, sync-off and retained pause/
minimize/tabs/expand/Focus/Stop have physical passes; see release142 for exact
final receipts and unqualified provider/widget checks. Use production sources; a
missing real fixture or absent native hook is unknown, not a passing playback
gate. No FPL workspace/data changes or TestFlight are authorized in this gate.

- Review Home artwork and personal Tonight/Full Matchday separation on wide,
  narrow and portrait iPad, dark/light and accessibility text. Preserve real
  crests/sport art and full identities, with no overlapping 44-point controls.
- Run `testPhysicalViewingSessionMinimizeBrowseReturnAndStop`: real playback,
  compact accessory, Matchday/Settings/Home, expand, Sources and Stop. Preserve
  actual native item/attempt when available; separately qualify provider video.
  Warm sports-plan/Matchday URLs must reveal Matchday and keep paused ownership.
  Raw XCTest `exists` is not VoiceOver focus proof: check ordinary hit-testing
  separately from an actual assistive traversal of the modal viewing region.
- Run `testPhysicalViewingWatchTwoIndependentSourcesAudioAndReturn`, then
  visually check usable picture sizes. Each pane opens its own picker; audio is
  exclusive; Swap/return preserves the retained owner. Test actual source changes
  and decoded output separately, not merely control existence.
- Repeat real native/provider PiP outside Fotty and return for at least60s,
  exact-source/item/attempt and ordinary Play/Pause/Stop. Do not erase141 CS6's
  failure with another source's success or unit-policy proof.
- Check Focus video in a short landscape window, compact viewing under Details,
  and final scene close. Covers/background must not retire media; actual scene
  teardown must not leave remote commands or orphaned transport.
- Sync remains off until owner opt-in. Validate real iCloud account initial sync,
  account change, conflicts/off behavior and plan import without resurrecting
  tombstones. All FPL IDs/state and device reminder consent stay excluded.
- The read-only native gallery check must not press its Add Widget footer or
  mutate the owner's Home layout. Signed shared storage and gallery discovery
  are distinct from installed timeline/filled-row/expiry evidence. Small family
  has one whole-widget URL; larger families have per-row Links. With a separately
  agreed saved plan/widget test, verify link resolution without autoplay and
  stale status expiry. No fake scores/overs.
  Real cross-device Handoff/sync require separately authorized current devices.

Build 82 was visually rejected: passing interaction audits did not establish
that the real phone matched the compact concept. For its native correction,
retain the rendered phone-grid height budget test, verify phone Sports overflow
and its absence on all-sports iPad layouts, then compare the actual phone Home
against the concept. Do not call a successful install visual acceptance.

Local calm-Home UI acceptance (not yet distributed): healthy listings must not
show a routine check-time banner. With stale CPL fixtures visible, retain the
short warning and Retry; reveal/hide the check timestamp through Update details.
Selecting football or searching for a non-CPL event must remove the CPL-only
notice. Failed/partial updates must retain available matches and controls;
starting a retry alone must not mark stale data fresh. Run the new stale-CPL,
offline and partial Catalyst journeys without suppressing notices, then repeat
large text and clipping checks. Physical iPhone/iPad acceptance must confirm
badge visibility, side Watch placement, readable full names and reminder targets.

Internal TestFlight build 81 is Testing for the unchanged seven-person `Fotty
Internal Smoke` group; build 80 remains the rollback. First verify build 81's
FPL duplicate/unchanged rejection, valid saved replacement after navigation and
preserved account data on both supported device classes. Before calling Champions
League playback qualified, install build 81 from TestFlight on both supported
device classes during a real match and verify: the official fixture is visible
before source publication without Watch; Watch appears once a concrete source
is published; duplicate provider rows collapse; startup/retry/source switching,
pause/play, audio and PiP continue to work. Also recheck immediate My Matchday
entry/scrolling, the reduced Settings copy and Home interests/countdown controls. The protected monitor proves
schedule/variant availability, not decoded media. UCL live score/minute and
goal/full-time alerts remain intentionally out of scope; start reminders remain
available.

TestFlight 75 and rejected private builds 76/77 reproduce a PiP window that stays
visible but cannot Play until Fotty foregrounds. Device tracing proves the
reproduced cricket provider uses WebKit-owned PiP: Fotty's scene-background
handler was explicitly suspending the owning HTML video. Private build 78 tracks
the confirmed web video's PiP state, gives it a 750 ms transition grace window
and rejects native handoff while WebKit PiP/background owns playback.

The owner repeated the previously failing provider-backed PiP path on build 78
and confirmed it is fixed on Jelani's iPhone. Build 78 is the accepted private
PiP baseline; builds 76/77 remain rejected and TestFlight remains build 75.
Future player changes must repeat PiP app-switch Pause/Play plus ordinary
non-PiP background/foreground behavior and preserve the same-source/no-duplicate-
audio contract. Automated lifecycle and simulator-free gates do not replace that
hardware regression check.

Internal TestFlight build 75 is Testing for `Fotty Internal Smoke` with all
seven existing testers. Apple processing, compliance, group assignment and
focused notes are complete; this proves availability, not installation. The
first exact-build pass must verify retained Home interests, selected PL/UCL/CPL
fixtures and kickoff times, cold/warm scrolling, one-tap cricket playback,
Pause/Play/audio/PiP background continuity, and current official FPL sync/Coach
evidence on at least one supported iPhone and iPad. Report any fixture failure
with screen, match, observed time and device.

Private build 74 is installed/launched only on Jet iPad. The owner physically
accepted build 73's primary personalization: PL/UCL/CPL selection removed
unrelated rows and retained a relevant fixture about one day away. Build 74
keeps selected live rows first and adds `Next 3 days`, with chronological
upcoming rows capped at four on iPad and three on iPhone. Its final simulator-free
suite/generic Release pass, CoreDevice reports 2.0.0 (74), and a screenshot shows
the active-interest state plus the new heading.

For remaining acceptance, use a provider window with selected fixtures on day
two or three; confirm they appear in kickoff order and that iPad never shows more
than four upcoming rows. See all and Search must retain the complete catalog.
Disable the switch and confirm broad Home still uses its compact six-hour/two-row
presentation. Then test removal of the last interest, relaunch persistence,
Light mode, large text and VoiceOver. Do not call an absent day-three row a bug
unless the provider catalog actually contains that fixture.

Private builds 68 and 69 were physically rejected for remaining Home stutter.
Build 70 rebuilds the catalog render structure around Apple's current lazy-stack
guidance and is installed/launched only on Jelani's iPhone as an optimized
Release build. Its simulator-free policy/Release gates pass and the main app plus
extension survived the process hold. Force-close it, reopen it and immediately
scroll Home through the cold catalog once; repeat warm, change sport filters,
open Full lineup, and return to Home. Exact pixel-position restoration was
intentionally removed because lazy-stack offsets are estimated and unstable.
A visible stop, freeze or multi-frame jump fails the candidate. If it fails,
restore compatible physical-device Instruments attachment before changing more
code; compare a repeatable trace rather than adding another speculative cache.
Jet iPad still runs private build 74 until it updates through TestFlight 75.

## Everyday usability and recovery acceptance (fourth local batch, 2026-09-05)

Private build 64 is installed and physically accepted for web Pause/Play,
provider Play and Sources on Jelani's iPhone. Jet iPad now runs private build 64,
but automation did not reach a player; repeat those controls and audible close
on a known decoded stream there before cross-device acceptance.
Do not confuse this focused playback evidence with the broader hands-on checklist
below. TestFlight build 75 carries the accumulated fixes but needs its own
physical acceptance.

Use the dated everyday-usability implementation record. The complete native gate
and all seven listed Catalyst journeys passed on 2026-09-05. For future candidates:

- Run the complete simulator-free unit/Release gate, then the Settings and
  Matchday Dynamic Type audits, Home sport-retention check, rapid navigation,
  Help/feedback, cricket discovery and Home discovery Catalyst checks.
- On one exact iPhone/iPad candidate, preserve Home filters and position through
  tab/app return; repeat for Search, Matchday and existing FPL workspaces.
- Check Light, Dark and System, accessibility text, VoiceOver, rotation, keyboard
  dismissal and 44-point actions. Playback/pitch may stay deliberately dark.
- Create an encrypted backup in Files, retain the file after relaunch, reject a
  wrong password without mutation, review the replacement summary, restore it
  and verify manager/follows/Matchday while reminders and Coach consent stay off.
- Send one report through the tester's real channel and confirm that the inviter
  received it. A copied report or opened share sheet is only prepared evidence.

This is the release checklist for Fotty 2.0. It uses Mac Catalyst and physical Apple devices only; do not start a simulator or install a UI-test runner on an iPhone or iPad.

## Complete FPL workspace acceptance (third local batch, 2026-09-04)

Use the dated FPL workspace implementation record for source-gate results.
Before release, qualify an explicitly authorized exact candidate:

- Confirm the intended manager after a legacy restore; verify existing scoped
  plans remain and unknown-origin bytes are not silently assigned or deleted.
- Compare two players, refresh, go offline and change selection mid-request.
  Current/retained/missing history must stay distinguishable without lost work.
- Open one rival during a live/locked GW and refresh. Both sides must use the
  same fixture/scoring packet, autosubs, captaincy and net transfer-hit convention.
  Offline results say LAST COMPLETE; standings do not claim real-time rank.
- Keep an edited wildcard/transfer plan while refreshing and navigating. Verify
  budget assumptions, changed-baseline warnings, chip windows and GW38 bounds.
- Save a next-GW journal decision while the current GW is live. Its target and
  historical Coach evidence date must remain explicit after reopening.
- Without cloud consent, ask a points/rules question and a strategy question;
  no paid call occurs. With separately approved paid allowance, evaluate named
  players outside the shortlist, ambiguous names, pronoun follow-ups, missing
  injury/minutes data and an illegal multi-transfer suggestion. Track actual
  responses/usage; offline mocked tests do not prove strategic model quality.

## Connected sports journey acceptance (second local batch, 2026-09-04)

Use `docs/audit/Fotty-Connected-Sports-Journey-2026-09-04.md` for exact automated
results. Before a release, separately authorize a uniquely numbered candidate:

- Find another sport without guessing its filter; follow a team and a league,
  restart, and verify Following on Home and Matchday, including legacy follows.
- Save/remind tomorrow's match, preserve it during a failed/partial refresh,
  recognize a changed start, and follow the actual notification into saved Matchday.
- Open a current CPL broadcast in one tap from Home, Search and saved Matchday.
  Exact source wins; recognized channels remain alternatives, never confirmed
  programming. An unavailable/conflicting event must not advertise empty playback.
- Pull to refresh scored and catalog-only details; verify coherent score/insights,
  real source withdrawal, retained old state on failure and no late overwrite
  after leaving. Confirm explicit empty differs from a failed or partial check.
- Verify compact rows, badges, Light/Dark/large text, VoiceOver, and usable
  reminder/refresh actions on owner-selected iPhone/iPad. Check failed-stream
  recovery does not suppress another match or replace still-playing media.

No new background reschedule service, device UI-runner or paid probe is part of
this source-only batch. Batch 3 FPL-tool completeness remains separate work.

## First private-product foundation batch (local source, 2026-09-04)

`docs/audit/Fotty-Foundation-Implementation-2026-09-04.md` records the combined
gate: full Catalyst units, generic iOS Release, all 83 web/Worker tests, Worker
dry-run and diff check pass. Temporary output is removed. This adds scoped relay,
private paid Coach and recoverable/validated transfer plans to the preceding five
local reliability repairs. Neither installed build 58 nor TestFlight 55 contains
the combined source; allocate a unique candidate before authorized distribution.

Before acceptance, exercise normal/WebKit native handoff and fallback, source
replacement/cancellation, provider controls, background/PiP and bounded continuity
on the explicitly selected iPhone/iPad. Check transfer edits through tab/app
return, official/deadline changes, Keep/Reset, Undo, manager switch and real backup
restore. Check Coach Access with Light/Dark/large text, lock/remove/reinstall and
secure paste; pure credential tests are not Keychain/UI acceptance.

Production protection is a separate gate. The new configuration is paid disabled
with a 50-attempt group UTC-day cap; local values/dry-run are not live evidence.
Use `docs/operations/PRIVATE-COACH-ACCESS.md` for owner-approved compatible rollout,
production version/binding/settings readback, denial/deterministic smokes and any
separately approved paid probe. No codes or real paid requests were used here.

## Default delivery and device acceptance

The first five deep-audit fixes and roadmap batches 1–4 are included in shared
TestFlight build 75. The latest direct-device split remains Jelani's iPhone on
build 70 and Jet iPad on build 74 until they update through TestFlight. Their
qualification and remaining physical acceptance are in the dated audit records
and `docs/releases/Fotty-2.0.0-75.md`.

The owner has approved the reliability-first next phase. Current local source
is **2.0.0 (75)** under the public name **Fotty Sports Hub**; Jelani's iPhone
has private **2.0.0 (70)** and Jet iPad has private **2.0.0 (74)**; shared
internal TestFlight
is **2.0.0 (75)**. Apple has processed build 75, saved its compliance and
focused notes, and attached only Fotty Internal Smoke. The group has seven
testers and build 75 preserves that exact membership. The
iPhone 16e retains private build 50. Build 65 is rejected for a scene-create
watchdog; build 66 retains build 64's physically accepted iPhone web-control
path and survives the startup watchdog on both owner devices. Its live-first
Home change and iPad/broader hands-on acceptance remain open. Build 72 adds
the priority-led Home hierarchy and safe reviewed-alias deduplication on Jet
iPad; its More-live, real-Premier-League and broader hands-on acceptance remain
open. Build 73 adds opt-in user-controlled Home interests and build 74 extends
that restricted view to a bounded three-day window without changing TestFlight.
Use `docs/releases/Fotty-2.0.0-75.md` for the current shared candidate,
`docs/releases/Fotty-2.0.0-74.md` for the preceding private candidate,
`docs/releases/Fotty-2.0.0-73.md` for the original personalized-Home candidate,
`docs/releases/Fotty-2.0.0-72.md` for the preceding Home-priority candidate,
`docs/releases/Fotty-2.0.0-65.md` for the rejected watchdog build,
`docs/releases/Fotty-2.0.0-64.md` for the preceding accepted web-control build,
`docs/releases/Fotty-2.0.0-59.md` for its original roadmap-install baseline, and
`docs/releases/Fotty-2.0.0-58.md` for the earlier direct-Score808 candidate status,
`docs/releases/Fotty-2.0.0-57.md` for the superseded inferred-route iPad pre-test,
`docs/releases/Fotty-2.0.0-56.md` for the preceding provider-trust iPad build,
`docs/releases/Fotty-2.0.0-55.md` for the preceding
Apple/TestFlight record, `docs/releases/Fotty-2.0.0-53.md` for the accepted
owner-iPhone one-tap CPL installation, `docs/releases/Fotty-2.0.0-51.md`
for the underlying CPL reliability release,
`docs/releases/Fotty-2.0.0-50.md` for the iPhone 16e record, and
`docs/releases/Fotty-2.0.0-47.md` for the earlier iPad baseline.

Build 75 is available to the existing internal group. On the exact TestFlight
update, verify the installed label reads `Fotty Sports Hub`, the Home masthead
reads `FOTTY` with `SPORTS HUB`, Settings shows the full name beside 2.0.0
(75), existing preferences remain, and the `fotty://` routes plus an older
`.fottybackup` remain compatible. Then repeat iPhone/iPad layout and live
playback/PiP checks; archive/upload evidence does not complete those gates.

When a provider catalog contains streams but all candidates fail certificate
trust, the app must identify a temporarily unavailable secure provider
connection rather than claim the catalog is empty. Never bypass the warning.
After the provider renews or changes host, retry the same fixture and verify a
normal resolution without rebuilding; a local-source fix must still receive a
unique build before physical UI acceptance.

Build 58 implements the direct-site investigation and removes build 57's
unverified donor mapping. The real production resolver passed during the reported
fixture; final simulator-free tests and generic iOS Release pass. Keep exact
teams/kickoff/timezone, stale page reuse, ambiguity, destination validation,
late availability, fair lane opportunity, partial failures and both provider-switch
directions in the regression gate. The shared validator now reads 8 KiB, but
generic HTML is not proof of decoded playback. Browser decoding and a matched
Watch page are not physical build-58 acceptance: verify the right live broadcast,
provider play/pause/unmute, source changes, recovery and background/PiP separately.
The reported fixture ended before the final private candidate could be tested.

The deep audit at `docs/audit/Fotty-Deep-App-Audit-2026-09-04.md` adds cross-system
transition gates: wrong-opponent/day rejection; pause/recover/close during retry;
retained alternative routes; FPL deadline/full-time without navigation; reverse-order
refresh completion; provider outage versus valid empty catalog; reminder delivery
and halftime transitions. These are open findings, not completed fixes.

Small scoped fixes use uniquely numbered, in-place private builds only on the
owner device explicitly selected for that check. Accumulate validated work over
several days; upload to TestFlight only when the combined change is a coherent,
significant user-visible or reliability milestone with focused tester notes.
Time alone is not sufficient, and urgent blockers require an explicit exception.
Follow `docs/RELEASE-PROCESS.md`, preserve installed data, never upload a
phone-only build or change another device implicitly, and allocate a higher
number for any changed source after an installed private build.

Shared-release acceptance uses the exact TestFlight update: verify version/build, launch, preserved preferences, narrow/Zoomed iPhone and iPad layouts, Coach keyboard, large text and current playback interactions. A separately authorized direct build may prove a narrow fix first, but it is not evidence for the TestFlight binary. The historical checked items below record prior evidence, not automatic certification of every later beta. Confirm one received TestFlight report before inviting more testers.

The next expansion is intentionally capped at 3–5 trusted testers for seven
consecutive days. Do not start that clock until the exact candidate passes the
entry gates in `docs/beta/PRIVATE-QUALIFICATION-2.0.md`, including Worker
`sourceVersion` read-back, native PiP app-switch/lock, encrypted Files restore,
a real live-stream recovery soak and changed-surface physical accessibility.
Keep iOS/iPadOS 26.4 as the private-cycle minimum.

## Private backup physical acceptance (build 48)

Use a physical device and the normal app; never a simulator or UI-test helper.

- Set a distinctive appearance/preferred sport, follow one team and league,
  save one dated match, and retain one manager-scoped FPL draft or scenario.
- In Settings → Privacy & Local Data → Private Backup, create a backup with a
  unique password of at least 12 characters. Save it through Files and verify
  the filename ends in `.fottybackup`.
- Change the seeded local state. Import the backup and try a wrong password;
  confirm it shows one controlled error and changes nothing.
- Unlock with the correct password. Review creation date, app/build, counts and
  manager before confirming. Cancel once and prove that cancel changes nothing.
- Confirm restore, then verify the selected preferences, follows, saved match
  identity and local FPL plan returned. The saved match must use only a current
  catalog route when later opened; the backup must not resurrect a stale source.
- Confirm all match reminders are off and Smart Coach requires consent again.
  Existing Coach conversation text, diagnostics and cached provider data must
  not return. Delete the test backup from Files when evidence is recorded.

Automated evidence covers encryption round-trip/wrong-password rejection,
excluded sensitive fields, valid replacement and invalid-payload atomicity. It
does not replace the Files picker, device storage or notification checks above.

## Automated release gate

### Structural graph and dead-code gate

- After a broad removal or module-boundary refactor, run Graphify code-only from a disposable environment and compare file/node/edge/community counts with `docs/audit/Fotty-Graphify-Dead-Code-and-Optimization-2026-08-31.md`. Review every partial-parse warning; require no newly detected import cycle.
- Run Knip from `web/`. The accepted false-positive/configuration list is only the dynamically registered `public/sw.js`, generated football catalog exports, the football URL-builder server/test re-export and Wrangler's `FootballQuotaBudget` binding. Investigate any new item rather than extending the list casually.
- Never delete solely because a graph node is weak or an export is not statically imported. Check Next routes, service-worker registration, Xcode target membership, Worker configuration, tests, generators and installed-data compatibility.
- Then run the complete simulator-free iOS gate plus web lint, unit tests, production build and Worker dry-run. Delete Graphify virtual environments, graphs, `.next` and bounded Xcode output after recording redacted results.

### Badge identity and motion gate (unreleased)

- Run `node tools/audit-team-badges.mjs` only as a deliberate live metadata gate. It must report valid artwork for every source-controlled football name and the complete NBA/WNBA/MLB/NHL/CPL/IPL catalogs, no provider failures, no broken image signatures and no suspicious shared URL. The script retains no images.
- Run `node tools/audit-live-provider-badges.mjs` before a shared badge release. It validates the exact opaque badge tokens present in the current live catalog through Fotty's provider image endpoint and retains no files. Empty provider badges are reported separately because they require known-artwork or monogram fallback coverage.
- Run the normal simulator-free `tools/ios-ci.sh` gate. Badge fallbacks, exact provider aliases, sport-profile mapping, motion policy and the absence of the retired P2P waiting vocabulary are unit contracts.
- On the next shared TestFlight artifact, select football, cricket and tennis on both iPhone and iPad. Confirm selection/load motion uses the right sport, rows never jump as badges arrive, Paris FC never shows Paris Saint-Germain artwork, monograms remain readable offline, and Reduce Motion produces a stable nonanimated state. Playing video and provider/native controls must remain unobstructed.

### Football identity and live-provider drift (private iPad build 47; shared release pending)

- Generate Swift and TypeScript from the reviewed seasonal manifest and fail if
  generated output, declared club counts, aliases or validity dates drift.
- Replay `provider-football-identity-vectors.json` in both product families. The
  exact `Brighton and Hove Albion` provider spelling must resolve to the same
  club as `Brighton & Hove Albion`; former/youth/current and cup cases must stay
  distinct.
- Run `node tools/audit-provider-football-identity.mjs --live` before a shared
  release. It must reach at least one catalog feed and report zero unresolved
  top-flight marker/team pairs. It is metadata-only and must not print or probe
  stream URLs.
- Where the official schedule matches both canonical teams within six hours,
  assert its competition overrides provider/catalog inference. Without that
  proof, require explicit markers or two current senior clubs and retain
  non-domestic exclusions.
- Exported diagnostics may show the redacted reason/source class only. They must
  not contain event/team names, fixture/source IDs, URLs or credentials.
- Evidence: the automated vectors and three-feed metadata precheck pass, and
  the pipeline is installed only on Jet iPad in private build 47. This does not
  certify physical discovery/league placement or a shared TestFlight binary.
  See `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md` and
  `docs/releases/Fotty-2.0.0-47.md`.

### Current Premier League membership (Unreleased)

- Assert the season-labelled official club set contains exactly 20 unique
  names. For 2026/27 it includes Coventry, Hull and Ipswich; it excludes Norwich
  plus relegated Burnley, West Ham and Wolves.
- A current/current fixture without metadata may use the Premier League roster
  fallback. Current/non-current and youth/reserve/women's fixtures must not.
- A provider's Premier League text cannot override a roster conflict. FA/EFL
  cups, Championship/lower divisions, friendlies and UEFA Europa/Conference
  remain outside the Premier League tab; explicit Champions League stays there.
- Keep legitimate non-Premier League broadcasts in All Football. Verify Home,
  club browsing/bootstrap and league-news inference use the same shared catalog.
- Evidence: `docs/audit/Fotty-Premier-League-Membership-2026-08-29.md`.

### Coach conversation ownership (Unreleased)

- Hold an injected reply, clear chat, then resolve it: nothing may reappear in
  memory or saved history. Disable consent and return a late failure: no fallback.
- Switch manager and begin another question before the old reply completes:
  only the new answer is stored and the old task cannot stop its loading state.
- Change squad, public/current gameweek, profile or rival mid-request: discard
  the outdated answer, explain why, and do not retry automatically.
- Recreate the FPL view while pending: navigation alone must preserve the task,
  input and context. Reject duplicate sends; preserve earlier follow-up messages.
- Test “What is my current total?” and equivalent explicit current-score wording
  in Swift and Worker. Undated/missing scoring stays unknown; ordinary future
  transfer/captain strategy still reaches the model stub. Never use paid calls
  to test request ownership. Evidence: `docs/audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md`.

### FPL published squad versus persistent local draft (build 44)

- Save a valid replacement, refresh full/foreground/matchday data and reopen:
  retain the draft, its manager/season, and the selected published/draft view.
- View a newly published deadline lineup without deleting the local plan. Keep
  the actual published gameweek visible; never score an older fallback against
  current live stats or treat draft multipliers/chips/history as official evidence.
- Recheck the 50-official/64-provisional goalkeeper-and-outfield autosub fixture
  before and after a hypothetical defender replacement: totals must not change.
- Reject duplicate/illegal replacements in the picker, keep the picker open
  with its reason, and never show a successful save after rejection. Exercise
  the actual UI using `testFPLSavedDraftAndPickerRejection` on Catalyst only.
- Preserve the original array for build-43 compatibility; a subsequent legacy
  edit must supersede stale companion context. Tests use isolated preferences;
  UI-fixture edits never persist in a real manager's defaults.
- Verify retained phone manager/draft/preferences before and after install,
  normal cold launch, narrow Squad source labels, and actual owner interaction.
  Public API absence before deadline publication is not a failed official save.

### Scheduled starts, compact rows and opt-in reminders (builds 39–41)

The countdown/reminder direction is now approved and implemented. The final
unit suite passes 184 tests with one optional HLS soak skipped and no runtime
warnings. Build and physical outcomes are recorded in `docs/releases/Fotty-2.0.0-41.md`.
Build 39's iPad inspection caught dimmed future names; build 40 presents the
names as readable information rather than the label of a disabled button.
Build 41 restores teams/badges left and Watch right. Saving uses the native
long-press menu/accessibility actions, not a permanent bookmark. Two scoped
Catalyst interaction tests pass, including silent save, Matchday return/removal,
channel saving and clipping/description audits. The UI runs retain two beta-Mac
main-thread warnings; they are not physical interaction certification.

- Check ordinary Home/lineup/channel rows at phone and iPad widths: Watch stays
  beside the information, not in an extra strip. Narrow/accessibility fallback
  may stack; full-width error/reminder explanations must stay readable. Long
  names and badges remain visible. Long-press Save/Remove must work on the iPad;
  saved data survives the update and no alert permission is requested by saving.
- Confirm passive Starts in before T−2 minutes, second precision inside five
  minutes, a source-backed play affordance at T−2 and Watch at T. No stream
  readiness guarantee, extra details screen, autoplay or extra provider polling.
- Save a match without receiving a prompt or scheduled reminder. Then tap
  Remind me: allow/deny permission and check truthful selected/error state.
  Opt-in saves the match; bell cancellation keeps it saved; unsave cancels both.
- Verify one scheduled alert survives a normal relaunch/locked device, tap it
  to return to the exact saved My Matchday row, and confirm no player starts.
  Dismissing a notification must not navigate. Check a removed target calmly.
- Check changed/unknown/cancelled starts, cancellation during a pending system
  response, no duplicate IDs, no overdue replay, and preservation of FPL alerts.
  Do not claim awareness of schedule changes while Fotty is closed.
- Exercise empty/failed resolution and inline Retry on the real iPad. Confirm
  channels stay usable and unknown/source-free fixtures do not claim playback.
- Light/dark/narrow previews are nonblank and inspected, but real large text,
  VoiceOver, bell taps, locked-device delivery and notification return require
  their own physical evidence. Never install a device UI-test helper.

### Appearance, sports identity and web transport (builds 36–38)

Build 38 was the prior installed iPad checkpoint. It has dedicated Appearance/no Engineering,
static NBA/MLB fallback/cache preservation, equal measured sport cells and all
sports inline on iPad, including Split View. Compact phones retain overflow.
155 unit tests pass with one optional skip and no runtime warnings; normal and
Review Safe Release plus signed Debug pass. Real Home confirms equal rows and
Yankees/Astros badges. Argument-free 20-second launch hold passes. A requested
Settings capture still showed Home and does not certify preference interaction;
the portrait masthead's scroll/safe-area state also needs a recheck.

Build 38 did not include countdown routing. The subsequently approved build-39
implementation and its separate physical acceptance are described above.

Keep Dark as the absent/invalid preference default. Verify Light and System in
Settings, return through every tab and presented form, and confirm the selection
survives relaunch without resetting the loaded FPL team/drafts. Check readable
text, selected sport/filter states, buttons and error/empty screens in both modes.
Pitch artwork and video stay dark; dismissing them must restore the chosen app
appearance. Home must show cached/provider team crests beside names and equipment
icons on sport tiles; channels/unpaired events must not invent opposing teams.

Unit regressions now resolve both light/dark palettes, verify real equipment
symbols, render bounded Home layouts and execute the injected playback script.
They are not substitutes for daylight, VoiceOver, scrolling or real touch tests.
On a decoded iPad provider feed, use the SAME centre or lower-left control for
pause and resume; compare Fotty's top-right state, wait beyond 20 seconds while
paused, and confirm no source switch/handoff resumes it. Verify unmute and popup
containment remain intact. A process hold alone never proves these interactions.

The owner explicitly requested normal-app iPad testing for this task; do not
expand it to the iPhone, simulator, device UI-test helper or TestFlight upload.
Exact outcomes and remaining acceptance are in the playback and appearance audit
records dated 2026-08-27. TestFlight remains build 35.

### Local all-sports Home patch

The approved Home concept is implemented locally, not distributed. See
`docs/audit/Fotty-All-Sports-Home-2026-08-27.md`. Validate All sports as the default,
visible next-start/activity summaries, More sports and selected-overflow
continuity, bounded mixed-sport Now & next, later-day fallback, See all on Home,
source-free Details, bookmarking and the separate personal Matchday. No source
variant or channel may inflate an event count. Retain CPL's checked-date label.
`HomeDiscoveryTests` in `BetaUsabilityTests.swift` covers policy, freshness,
identity, non-team titles and actual tile-color contrast. The explicit Debug
Home UI fixture is network-free and non-persistent.

Run all six Dashboard accessibility scopes and
`testHomeDiscoveryShowsActivityFiltersAndFullLineup` on Catalyst, alongside the
cricket channel journey. The beta-Mac contrast analyzer still reports fixed
high-contrast text despite captured-pixel and >=7:1 palette evidence. New trial
exceptions were removed; do not report that audit as clean. The final-source
gate passes 140 unit tests (one opt-in soak skipped), eight selected UI checks
(five non-contrast Home audits plus Home, cricket and setup journeys), and
unsigned normal/ReviewSafe iOS compilation. Sampled UI runs retain a main-thread
responsiveness runtime warning. Fresh TestFlight iPhone/iPad large-text, Zoom,
contrast and interaction acceptance remain separate gates. No light-mode
capability is enabled by this patch.

### Local cricket/tab-separation patch

The 27 August post-build-35 patch is not yet distributed. See
`docs/audit/Fotty-Cricket-and-Tab-Separation-2026-08-27.md` for its final-source
checks. Before its next TestFlight upload, recheck CPL league announcements.
On the TestFlight update, verify Home → Cricket filters, a saved Willow channel
in My Matchday, channel playback/control placement on iPhone/iPad, and preserved
FPL state in its own tab. Never interpret a channel listing as a confirmed CPL
programme or Catalyst playback as physical-device acceptance.

From the repository root:

```bash
tools/ios-device-qa.sh --skip-deploy

cd web
npm run test:unit
```

Run the eleven `FottyNavigationUITests` accessibility audits—six Dashboard scopes plus direct FPL, Matchday, Settings, Match Center, and Player Dynamic Type—and the rapid-navigation check individually on Mac Catalyst. Catalyst UI automation may request local macOS authentication; canceling that prompt is a harness failure, not an audit result. Never substitute a simulator run.

The runner also includes three beta-usability journeys: native Help/reporting,
FPL link entry without implicit connection, and setup navigation/dismissal.
See `docs/BETA-TESTER-GUIDE.md` for the fresh-user/recovery matrix and actual
TestFlight feedback receipt gate. A local passing test does not prove that a
report reached the owner's inbox or App Store Connect.

Catalyst interaction checks must use mouse clicks for native controls and assert
the resulting screen or selected tab. A synthesized touch tap can move the Mac
pointer without activating a control; the continued existence of a tab button
does not prove navigation. Keep Fotty foregrounded while these checks run.

The guarded runner exits before invoking XCTest when the Mac is locked:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  tools/catalyst-ui-release-gate.sh
```

Build 33 passed this complete runner in one invocation on 2026-08-26: all
eleven accessibility audits plus rapid navigation/foreground recovery. The
runner used no simulator or retry and deleted its owned DerivedData on exit.

The unreleased 2026-08-27 usability patch passed 117 policy tests (one opt-in HLS
soak skipped), both generic-iOS Release configurations, and all three new beta
journeys. Its corrected tab-selection test, Dashboard contrast/traits and Settings
Dynamic Type checks also passed. See the Decisions Log for the exact scope and
remaining beta-Mac runtime warnings. This does not extend build 33's physical
acceptance to a new distribution: check the new flows on supported hardware and
confirm a received TestFlight report before widening the tester group.

Only for explicitly requested direct-device debugging, generic iOS compile, signed installation and launch:

```bash
tools/ios-device-qa.sh \
  --device <iphone-coredevice-id> \
  --device <ipad-coredevice-id>
```

The script builds one signed universal Debug artifact, strictly verifies its seal, and installs that exact normal Fotty app on every requested device. It does not install `FottyUITests-Runner`.

After an install, the lock-aware physical process gate rejects simulators and
holds only the normal Fotty app in the foreground:

```bash
tools/ios-physical-launch-hold.sh \
  --device <physical-coredevice-id> \
  --hold-seconds 60
```

Process survival is only the cold-launch/watchdog gate; complete the visual,
audio, PiP, notification, and interaction checklist manually on the device.

For repeatable visual routing in a signed Debug normal app, terminate the
existing Fotty process and launch with `fotty://fpl` plus one bounded workspace
argument: `--fotty-fpl-workspace Plan`, `Squad`, `Coach`, or `Tools`. Release
builds ignore this QA-only argument. This is normal-app navigation only; it does
not synthesize touches or install `FottyUITests-Runner`, so keyboard, audio,
provider controls, and other interaction claims still require a person.

## Journey 1 — discover and open a match

- [x] Home has one clear `Now & next` lead and one broad live/upcoming schedule; completed fixtures do not remain scheduled content.
- [x] A `LIVE` row has a supported catalog broadcast, the whole row is actionable, and Watch opens source resolution.
- [x] A source-less active fixture says `IN PLAY` and opens Match Center rather than a dead player.
- [x] Dense fixture rows keep recognizable club names; avoid ambiguous first-letter forms such as `L. City` when a common short name exists.
- [x] `Watch 2` is hidden unless at least two otherwise-eligible events are live or within 30 minutes of kickoff and their provider families have recent decoded success.
- [x] Matchday contains only saved, followed-team, and current FPL-squad fixtures, including its bounded Recent section.
- [x] Notification taps, Matchday rows, Home rows, Match Center, and playback resolve the same fixture and teams.
- [x] Non-Premier-League rows do not say that a score is unavailable; Fotty did not promise score coverage there.

## Journey 2 — start and keep playback

- [x] A selected numbered broadcast remains selected while it negotiates the full startup window.
- [x] Provider play, pause, seek/fullscreen when offered, and `Tap to unmute` controls respond directly; Fotty does not cover the web player with a full-screen tap target.
- [x] Popups and known ad-navigation chains are contained without removing legitimate provider controls. Provider-owned in-video advertising is not presented as app-controlled.
- [x] A short pause, network transition, or recovered decoded stream does not trigger an unsolicited source replacement.
- [x] One same-source startup retry occurs before automatic failover; manual source selection always remains available.
- [x] When a verified HLS/MP4 candidate appears, native handoff has no visible jump. A later native failure returns to the same web broadcast before trying another provider.
- [x] PiP, AirPlay, and Live Activity are offered only after native capability is proven. Closing playback ends the activity and leaves no duplicate audio or ticking sound.
- [ ] With a real native handoff already playing in PiP, open a different app for at least 60 seconds and lock/unlock once. Video/audio must continue in the system window without a Fotty resume, source change or duplicate audio. This is a physical acceptance gate for the 2026-08-30 correction.
- [x] Backgrounding a web embed pauses provider/ad audio; foregrounding resumes the same selected broadcast without an unsolicited source change.
- [x] Terminal copy distinguishes device network loss, explicit provider unavailability, slow startup, unsupported media, and exhausted Fotty recovery.
- [x] A deferred opaque provider-frame failure becomes `Startup timeout` only after the complete 20-second window; an explicit provider rejection keeps its original reason.
- [x] Settings → Quality & Diagnostics records the attempt, proven start/recovery/failure, and exports only redacted local evidence.

## Journey 3 — prepare for the FPL deadline

- [x] Plan shows the official squad, local deadline, bank, estimated free transfers, validation, flags, and freshness/source.
- [x] Squad lenses switch between next fixture, modeled points, expected minutes, official form, ownership, price movement, and live points without clipping on iPhone.
- [x] Transfer Lab compares Roll, one-move, and two-move routes week by week with hit cost, break-even, downside, assumptions, confidence, and validation.
- [x] Named scenarios persist only for the current manager and season and never imply an official FPL submission.
- [x] Smart Coach Send and Return dismiss the keyboard and preserve the response at standard Dynamic Type.
- [x] Smart Coach quick prompts share the focus-clearing send path, and a structured response remains visible through the Plan/Squad/Coach/Tools large-Dynamic-Type audit.
- [x] Direct rules, deadline, captain, bench, selling-price, free-transfer, and current-points questions use the local/rules route with zero DeepSeek tokens.
- [x] A model answer includes evidence, downside, checks, freshness, source/model, and token usage; malformed, stale, contradictory, or incomplete output falls back safely.

## Journey 4 — follow the live gameweek

- [x] Live Points shows official current points first and labels a different deterministic total `PROVISIONAL`.
- [x] Goalkeeper and legal outfield autosubs are named in/out; double-gameweek players are not declared absent while a fixture remains.
- [x] Captain failure promotes a played vice-captain even when no bench replacement is possible. Bench Boost creates no autosubs. Transfer cost is deducted.
- [x] Published `automatic_subs` or a finished/data-checked event replaces every Fotty projection with official truth.
- [x] Rival Race uses only published post-deadline squads and separates official standings from live/modelled implications.
- [x] Match Center's FPL Match Lens agrees with the device-local squad and already-loaded live snapshot.

## Journey 5 — review and improve

- [x] Review records confirmed points, rank, transfer cost, bench points, captain return, and top scorer from official data.
- [x] Decision Journal entries and reflections remain manager/season scoped.
- [x] The latest reflection appears as a process lesson in the next Plan cycle without claiming the result proves causation.
- [x] Saved scenarios remain available for comparison but are clearly dated/model-versioned assumptions.

## Native system and form-factor checks

- [x] Spoiler-safe goal/full-time alerts never expose a score or the word `goal`; ordinary alerts contain the expected result.
- [x] The small and medium FPL deadline widgets show the official deadline/source and `fotty://fpl` opens the FPL tab.
- [x] An eligible Live Activity begins only after PiP is actually active and shows matchup, score, match phase, and a return cue; web embeds and ordinary foreground playback never create one.
- [x] PiP stop/failure while backgrounded pauses native playback and removes the Live Activity; temporary inactive scenes do not force PiP.
- [x] Typed Live Activity return-route tests reveal an existing matching player, or open that match's Match Center after a cold relaunch; the owner also confirmed the real system-surface return opened the correct match/player.
- [x] Cold-launch iPad for at least 60 seconds: Home remains responsive, one bounded refresh path runs, and no `0x8BADF00D` occurs.
- [x] On iPhone and iPad, inspect Home, Matchday, Match Center, Player, FPL Plan/Live/Review, Squad, Coach, Tools, and Settings at standard and large Dynamic Type; owner-confirmed on 2026-08-26.
- [x] On Mac Catalyst without a simulator, every named surface above passes the release-scope large-Dynamic-Type audit using direct deterministic presentation where live/account data is not appropriate.
- [x] VoiceOver descriptions, hit regions, contrast, element detection, and text clipping have no unresolved release-scope finding.

### Completed direct physical procedure

These checks use the installed normal app, not `FottyUITests-Runner` or a
simulator. CoreDevice launch/capture is not accepted as interaction evidence
because it cannot change Dynamic Type or tap a system surface.

1. On each form factor, note the existing text-size setting. In Settings →
   Accessibility → Display & Text Size → Larger Text, enable the accessibility
   sizes and select a clearly large size. Open Home, Matchday, Match Center,
   Player, FPL Plan/Live/Review, Squad, Coach, Tools, and Settings. Scroll and
   activate the primary action on each screen; verify content is not clipped,
   overlapped, unreachable, or replaced by unlabeled icon-only controls. On
   Coach, send one deterministic rules prompt and verify the keyboard can be
   dismissed and the answer read. Restore the owner's original text-size
   setting afterward.
2. Use a real source that completes native handoff; an ordinary WebKit embed is
   intentionally ineligible. Enter PiP and confirm the useful Live Activity.
   With the matching player still alive, tap the activity and verify it reveals
   that player without stacking a second sheet. Repeat after terminating Fotty:
   tapping the remaining system surface must cold-open the same match's Match
   Center, and stopping playback must remove the activity.
3. During an eligible followed Premier League fixture, tap one real Fotty alert
   and verify the same canonical match opens. Preserve spoiler-safe content for
   spoiler-safe alerts. Do not substitute CoreDevice's Darwin-notification
   command; it is not a user-notification interaction.
4. Record only build, device form factor, timestamp, route/result, and whether
   the action passed. Do not retain lock-screen screenshots, private stream
   URLs, notification content, or temporary device captures.

## Release evidence

- [x] Debug and the single Release generic physical-iOS graph compile; the retired `APP_REVIEW_SAFE` graph is absent.
- [x] Normal Fotty installs and launches on the supported physical iPhone and iPad; CoreDevice reports `2.0.0 (33)` and observes the exact normal app for a bounded 60-second hold on each target.
- [x] Active-match evidence records provider family, timestamp, decoded result, source changes, audible-unmute result, interruption recovery, native/PiP availability, and teardown without a private stream URL.
- [x] During an eligible followed Premier League fixture, the owner confirmed the real alert/Live Activity tap returned to the correct match/player without retaining notification content or a private stream URL.
- [x] Revoke the historically exposed Cloudflare tunnel credential; the owner-authorized deletion removed its exact retired tunnel and left the Fotty Worker healthy.
- [x] GitHub Support closed ticket `#4701297` after purging the retained objects. Both obsolete commits return `No commit found` through the authenticated API and HTTP 404 through the public web UI; all four PR refs are absent; a fresh heads/tags clone contains neither commit nor `cert.json`; `main` and tags did not move.
- [x] `git diff --check`, Worker/web unit tests, Swift unit/policy tests, and release-scope accessibility audits pass.
- [x] `CHANGELOG.md`, Roadmap, Risks, Architecture Map, Project Memory, Decisions Log, and the 2.0 completion report agree on build 33 and its single remaining Git-history security gate.

## Build-49 whole-app qualification gate (open, 2026-08-31)

Run this as one named release-candidate pass; earlier hardware evidence is useful history but does not replace exact-build acceptance.

- [x] Simulator-free iOS unit/policy suite and generic unsigned Release build pass with two Xcode jobs and owned DerivedData cleanup.
- [x] Web/Worker unit suite passes 74/74; Worker dry-run packages; production `/health` responds.
- [x] Reviewed badge artwork passes 272/272 and all 128 current live provider badge tokens return valid image data without retaining images.
- [ ] On iPhone and iPad, export an encrypted backup through Files, reject a wrong password, review its summary, restore over meaningful existing data, relaunch and confirm replacement/consent/reminder behavior.
- [ ] On an actually decoding native source, enter PiP, open another app, lock/unlock, return to Fotty and stop playback. Confirm one audio stream, one player and correct Live Activity cleanup throughout.
- [ ] During a live event, soak pause/resume, mute/unmute, orientation, brief network loss, recovery and an explicit source change. Confirm Fotty never replaces a healthy selected source merely because an observer is temporarily blind.
- [ ] On both form factors, review Dark/Light/System, accessibility text, Reduce Motion and VoiceOver across Home, Search, Matchday, Player, Match Center, FPL and Settings.
- [ ] Give one uncoached tester five tasks: find/watch non-football, save/remind an upcoming event, return through the reminder, connect/explain FPL published-versus-draft, and prepare a problem report.
- [ ] Record the exact Worker deployment identifier alongside the app build; current health has no code-version field and cannot close this item.
- [ ] Reconcile App Privacy declarations against every field transmitted to the Worker and every field retained only on device.
## Fixture freshness gate (local after private build 74)

- Run `node tools/audit-cpl-fixtures.mjs --live`; require all 39 fixture
  identities/kickoffs to pass and investigate every unreviewed source conflict.
- Run `node tools/audit-football-fixture-feed.mjs`; require valid nonempty current
  season PL and CL feeds with unique IDs, teams, competition identity and UTC
  dates.
- In Worker tests, prove an unchanged successful CPL check advances `checkedAt`
  without changing `revision`, while a source outage preserves the fallback's
  old receipt and `last-known-good` status.
- In iOS tests, prove bundled/fallback CPL never claims freshness, verified CPL
  expires after two hours, an older/lower-trust candidate cannot downgrade cache,
  and football schedule failure/age returns truthful notices.
- Before release, deploy the Worker and verify `/health` reports
  `2026-09-06.fixture-freshness-1`; then query the CPL route twice and confirm a
  current `checkedAt`. App UI/state changes require a new allocated build and
  physical refresh-warning/current-state acceptance.
