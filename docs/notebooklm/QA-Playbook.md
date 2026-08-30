# Fotty QA Playbook

Last updated: 2026-08-30

This is the release checklist for Fotty 2.0. It uses Mac Catalyst and physical Apple devices only; do not start a simulator or install a UI-test runner on an iPhone or iPad.

## Default delivery and device acceptance

The owner has approved the reliability-first next phase. Current local source
and internal distribution are **2.0.0 (46)**. Apple independently shows the
build Internal / Testing for Fotty Internal Smoke with the unchanged two testers.
Physical TestFlight use exposed build 45's retired review-safe vocabulary; do
not treat 45 as an acceptance candidate. Use
`docs/releases/Fotty-2.0.0-46.md` for the current Apple/install record and
`docs/audit/Fotty-Single-Product-Graph-2026-08-29.md` for the correction.

Build 46 has one product graph and passes the final-source Catalyst unit suite,
vocabulary/retired-symbol gates and generic iOS Release compile. Its Catalyst
Home UI test could not begin because the beta-Mac automation runner timed out
twice. A direct read confirms build 46 is installed on the connected iPad; the
iPhone remains build 44 after TestFlight was reopened. After the iPhone Update,
read its version and physically confirm Home/Football/league vocabulary plus
Watch, Matchday and FPL availability after a cold launch on both devices before
the beta expands. Historical checkpoint notes below retain their at-the-time
evidence only.

The owner now prefers phone-first validation for small scoped fixes, followed by deliberately batched shared TestFlight updates. Follow `docs/RELEASE-PROCESS.md`; verify the latest build number for either route, preserve installed data, and never upload a phone-only build or change another device implicitly. Build 44 is the approved iPhone-only FPL correction; its exact status is in `docs/releases/Fotty-2.0.0-44.md`. Shared releases use the single normal Release archive/upload and independent Apple processing/group checks.

Physical acceptance uses the exact TestFlight update: verify version/build, launch, preserved preferences, narrow/Zoomed iPhone and iPad layouts, Coach keyboard, large text and current playback interactions. The historical checked items below record prior evidence, not automatic certification of every later beta. Confirm one received TestFlight report before inviting more testers.

## Automated release gate

### Football identity and live-provider drift (Unreleased)

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
- Evidence: `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md`.

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
