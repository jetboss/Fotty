# Changelog

All notable Fotty changes are recorded here. Releases follow Semantic Versioning,
while the Apple bundle build number increases for every distributed build.

## [Unreleased]

- Private Jet iPad 2.0.1 (214): repair source-qualified CS/Willow limited-overs matching and explicit official match-number handling; group Willow/Fox/Sky Cricket inside Sports TV while preserving their existing resolvers and personal order. Publish approved PR116 cricket Worker/watchdog repair with activation/state retained. Fox delivery and fresh live-match acceptance remain separate open gates; no TestFlight release.

- Private Jet iPad 2.0.1 (212): add qualified English beIN SPORTS XTRA through the existing reviewed TV adapter. Preserve existing stations, source choices and delivery guards; exclude CBS Golazo, Fubo Sports Network and separate Willow Sports after their current media returned403. No TestFlight release.

- Private Jet iPad 2.0.1 (210): add the verified CS Sky Sports Football delivery to normal Watch, prefer it over the incompatible TV feed on a cold tie, scope single-player TV startup history to each station, renew a verified frozen TV window once, and ignore late failures after a terminal attempt.

- Private Jet iPad candidate 2.0.1 (141): match official football scores and
  freshness by full club identity while retaining short display labels and
  squad/date safeguards. Stabilize equivalent CS segment wrappers only for
  the verified maintainer contract, retaining signed tokens, original media,
  captured headers and existing destination checks. Add finite native HLS
  failure classification and regression tests. Device playback and PiP
  qualification are a separate private gate; no TestFlight release. The longer
  build139 device check exposed the same wrapper rotation on a verified TikTok
  CDN image segment;140 includes that exact-host compatibility regression.
  Build141 also retains available CS upstreams within the six-choice cap,
  preserving admission, delivery order, signed URLs and runtime profiles.

- Prepare private Jelani-iPhone build 2.0.1 (124) with the source-qualified
  all-sport status, cache/identity, stream/bookmark continuity and compact
  upcoming/channel row repairs. Backend registry/polling/monitor changes remain
  staged and are not activated by this phone-only installation. Preserve the
  data container, existing source flags, badges and sport artwork; no TestFlight,
  other-device installation, new feed activation or FPL feature work.

- Release internal TestFlight 2.0.1 (111), consolidating the privately validated
  101–110 app-wide polish and reliability work into one shared candidate. The
  batch includes adaptive iPhone/iPad layouts, native Liquid Glass navigation,
  badge-led Home hierarchy, compact live/up-next presentation, consistent sports
  artwork, Watch Two improvements, quieter truthful catalog/fixture messaging,
  interest-filter recovery and corrected CPL playoff identity. Production Worker
  source `2026-09-20.worker-stability-1` is already deployed with bounded upstream
  calls, structured observability, direct catalog fallback and exact-version
  health monitoring. Keep the release internal-only and preserve the existing
  Fotty Internal Smoke group. Apple processed the build, accepted the established
  compliance declaration and shows it as Testing with focused English (U.K.)
  notes saved. Build 100 remains the fallback; exact TestFlight device acceptance
  remains separate.

- Private Jelani-iPhone build 2.0.1 (109): use the working Liquid Glass surface
  as Fotty's real Home/Matchday/FPL/Settings tab bar instead of layering an empty
  native bar behind a custom dock. Recompose three-column sport tiles so artwork
  sits above full-width labels, and render paired-badge fixtures with one readable
  line per team plus scaled reflow before countdown/reminder actions. Full
  simulator-free CI, the 361-point rendered grid contract and signed optimized
  device gate pass. CoreDevice confirms 109 running; exact-build light and dark
  screenshots verify the native tab bar and match-name correction. No TestFlight
  or iPad action.

- Private Jelani-iPhone build 2.0.1 (107): complete the physical Home verification
  started in 105 and remove an iOS 27 empty Liquid Glass tab capsule above Fotty's
  custom dock. Root destinations now remain alive in a layered container without
  an underlying system `TabView`; only the selected layer is visible, interactive
  or exposed to accessibility. Remove the redundant sport-tile checkmark. Full
  simulator-free CI and the signed optimized device gate pass; CoreDevice confirms
  107 running on Jelani's iPhone and a fresh physical screenshot confirms the
  capsule is gone. No TestFlight or iPad action.

- Private Jelani-iPhone build 2.0.1 (105): implement the owner-approved
  Apple-inspired Home hierarchy natively. A real-badge live panel now leads,
  Up Next uses compact paired-badge rows, Browse Sports follows with full-colour
  Apple equipment artwork, and Search/Watch Two use restrained material chrome.
  Existing stream, reminder, sorting, interests, Matchday and player ownership
  remain unchanged. The focused rendered phone-grid regression and complete
  simulator-free iOS CI gate pass. The signed optimized build installs in place
  and CoreDevice reports 2.0.1 (105) on Jelani's iPhone; launch/visual acceptance
  remains pending because the phone re-locked. No TestFlight or iPad action.

- Prepare private Fotty 2.0.1 (104) as the playback-confidence candidate. Carry
  forward build 103's video-first Watch Two layout and add the missing
  build-scoped quality evidence for both MultiView panels: attempts, decoded
  starts, in-place recoveries, automatic source changes, terminal failures and
  startup time now use the same privacy-safe contract as the normal player.
  Add a release-identity regression so the app, Live Activity extension,
  Xcode project and XcodeGen source cannot silently diverge. Complete
  simulator-free CI passes, as do the live PL/Champions League fixture contract,
  official CPL schedule comparison and three-feed football identity audit.
  Repair the opt-in playback soak after dead-code cleanup removed its old URL
  helper; the gate now owns a reachable public Apple HLS fixture and the final
  120-second run keeps one request, source and player item with decoded progress
  and zero automatic failovers.
  Exact Jet iPad interaction and signed-install evidence are recorded in the
  release note; no TestFlight upload is part of this private qualification.

- Private Jet iPad build 2.0.0 (101): complete the post-100 app-wide
  Apple-aligned UI pass across Home, Matchday, Search, FPL, Settings, Match Hub
  and player presentation. Preserve existing sports art, grid and playback
  ownership while improving adaptive labels, control feedback, contrast,
  large-text layouts, Coach keyboard avoidance and source-retry consistency.
  The source gate passes 586 Catalyst tests with two opt-in skips and an unsigned
  iOS Release compile. A signed optimized Release is installed in place on Jet
  iPad only; app/extension identity, signatures, 60-second launch stability,
  zero Fotty crash logs and physical landscape Home, Matchday, FPL onboarding
  and Settings presentation pass with retained data.
  Subsequent device acceptance confirms the connected FPL manager ID and
  current-season confirmation persist across a full Fotty terminate/relaunch;
  the connected Live workspace reopens without re-entry. No TestFlight upload,
  tester change or data reset.

- Release internal TestFlight 2.0.0 (100), batching opt-in CS playback and the
  post-93 feedback/reminder work using official Xcode 27 (27A266a), following
  rejection of 99's beta SDK. 581 units pass, two opt-in skips; iOS Release,
  signed archive and upload pass. Apple confirms Testing for the existing
  11-person Fotty Internal Smoke group with CS test notes saved. Build 93 remains
  available. Temporary output/installer removed; exact-device acceptance remains
  open. See release 100.

- Candidate 2.0.0 (99) batches opt-in CS playback and post-93 feedback/reminder
  work. Full units: 581 pass, two opt-in skips; iOS Release and signed archive
  pass. Apple rejected the installed old beta SDK, so it is not on TestFlight.
  Xcode update approved; candidate 100 follows. Source receipt retained and
  temporary output removed; see release 99.

- Private Jet iPad build 2.0.0 (98): integrate opt-in CS options with shared
  native/web routing, bounded native retry, cancelled-attempt protection,
  deferred PiP callbacks, exact Live-catalog fallback/conflict admission and
  private source attribution. Focused tests: 181 pass, one opt-in soak skip;
  signed Release and install/launch checks pass. Owner confirmed CS2 playback,
  controls, source switching and PiP on Jet iPad. Other-source/iPhone/long-soak
  acceptance remains open. No TestFlight upload; see release 98.

- Source-only follow-up after 93: include bounded, dated MetricKit scrolling/hang
  summaries in the existing opt-in feedback export, with unknown/mixed build
  attribution, expiry, clearing and no raw traces or automatic upload. Full
  Catalyst gate: 546 pass, zero failures, two opt-in skips; iOS Release passes.
  Add tested history-free source recovery and pre-upload drift comparison, a
  verified 17 MB local post-release recovery bundle, and an independent build-93
  acceptance/report-receipt ledger. The owner-approved private GitHub recovery
  copy subsequently passed a fresh download/restore; backups are manual and real
  tester acceptance remains open. No new app install or distribution; see the
  9 September field-readiness audit.

- Release internal TestFlight build 2.0.0 (93), batching the private
  82–92 UI work: compact Home and sport tiles, app-wide grouping and team
  identity, adaptive iPad layouts, optional kickoff-clash hints, consistent
  current/upcoming clocks, quieter routine refreshes and shaded sport loading
  animations with evidence-gated Champions League styling. No playback
  transport, provider, backend or tester-access changes in this release task.
  Full Catalyst units: 538 pass, two opt-in checks skip; four refreshed UI checks
  pass after one unchanged test-clock retry. Public Xcode 26.6 signs and uploads
  the archive; Apple confirms Internal / Testing for the unchanged eight-person
  Fotty Internal Smoke group, with focused testing notes. Build 81 stays available.
  The 2.3 GB owned release output is removed. See release 93; direct device
  acceptance of private 92 is not certification of the TestFlight artifact.

- Correct the native Home design after build 82's visual rejection: local
  Dynamic Type-aware point sizes instead of semantic font buckets, smaller
  equal-height sports tiles without reserved blank title lines, compact Fotty
  header with plain Search, and phone overflow in the header instead of a
  separate row. Keep badges, side Watch and reminder controls. Real iPhone
  comparison of intermediate build 83 caught four-column Pro Max layout;
  cap phones at three columns while retaining adaptive iPad capacity. Add
  native-rendered grid height and wide-phone column regression checks.

- Local calm-Home UI batch: remove the repeated masthead tagline and interests
  subtitle, use a compact interests row and quieter grouped match rows, and keep
  badges, side-aligned Watch and opt-in reminders. Fresh listings show no routine
  status banner; meaningful update warnings are shorter and check times are
  behind Update details. CPL warnings follow the displayed fixtures in Home,
  Search and Matchday. Automated UI fixtures now exercise fresh, stale, offline
  and partial states rather than hiding notices. No new distributed build.

- Prepare internal candidate 2.0.0 (81) from one reproducible product graph.
  FPL squad replacement now rejects the currently selected player and any player
  already in the squad, keeps the chooser open with an accessible explanation,
  and preserves a valid saved replacement across navigation. Automated FPL data
  remains isolated from real account freshness rules. Add stable identifiers for
  Home interests, sport/event status, match-start controls and FPL squad rows;
  tighten the Catalyst contrast audit to numeric colour contracts and retain
  failure-only UI evidence plus richer release-gate diagnostics. The exact
  candidate replays from clean remote ancestry with no omitted files and passes
  secret scanning, 22 memory tests, the complete simulator-free public-Xcode
  unit/Release gate, and all 20 Xcode 27 Catalyst UI journeys. Build 80 remains
  the rollback. Public Xcode 26.6 archived and uploaded the internal-only build;
  Apple completed processing, accepted the established no-listed-encryption
  declaration, saved focused What to Test notes, and shows build 81 Testing for
  the unchanged seven-person `Fotty Internal Smoke` group. Real Champions
  League match-time playback and hands-on TestFlight iPhone/iPad acceptance
  remain separate gates.

- Prepare internal candidate 2.0.0 (80) and harden the 2026/27 Champions League
  path after build 79. All 36 official club
  identities now resolve across the 17 formal football-data.org name variants;
  source-free official fixtures join Home, Search and My Matchday before stream
  publication without exposing Watch. Different provider IDs for the exact same
  reviewed teams/kickoff collapse to one source-backed row. Add an imminent UCL
  CI preflight across the official schedule, three catalog mirrors and Worker
  variants. Protected PR 21 publishes a daily 72-hour report plus a dedicated
  30-minute match-window workflow; its policy rejects the Worker's synthetic
  Legacy fallback and includes the player-supported Admin source. The hosted
  preflight found all 18 Matchday 1 fixtures with three concrete variants each,
  and the complete simulator-free policy suite plus public-Xcode 26.6 signed
  Release compile pass. Public Xcode 26.6 archived and uploaded the internal-only
  build; Apple processed it, the established no-listed-encryption declaration
  and focused notes were saved, and build 80 is Testing for the unchanged
  seven-person `Fotty Internal Smoke` group. Build 79 remains the rollback.
  Live UCL score/alert coverage and real match-time device playback remain
  separate gates.

- Release internal candidate 2.0.0 (79). My Matchday now builds one
  revision-keyed presentation projection instead of re-running official-match,
  interest, status, playback and sort work whenever SwiftUI redraws. Per-frame
  scroll-offset persistence and root-tab animation are removed. Settings keeps
  action/state, privacy, destructive and recovery copy while removing repeated
  instructions and built-in source version details. The complete simulator-free
  policy suite, live identity audit and generic iOS Release compile pass. The
  signed build installed on Jelani's iPhone and Jet iPad; automatic iPhone
  launch was denied because it was locked, while the iPad installation and
  launch succeeded. Public Xcode 26.6 archived and uploaded the same source;
  Apple processed it, the established no-listed-encryption declaration was
  saved, and build 79 is Testing for the unchanged seven-person
  `Fotty Internal Smoke` group. Hands-on Matchday acceptance remains open and
  temporary build products were removed.

- Allocate private iPhone candidate 2.0.0 (78) after physical tracing proved the
  failing cricket PiP session is WebKit-owned. The confirmed HTML video now
  reports its PiP lifecycle to Fotty; WebKit PiP cancels scene-background media
  suspension and prevents the asynchronous native handoff from dismantling the
  owning web view. Ordinary non-PiP background playback still suspends after a
  bounded grace window. WebKit execution/bridge/lifecycle regressions and the
  complete simulator-free unit/Release gate pass. The signed optimized build is
  installed only on Jelani's iPhone; the owner repeated the previously failing
  provider PiP path and confirmed it is fixed. Build 78 is the accepted private
  baseline, TestFlight remains build 75, and all temporary products were removed.

- Allocate private iPhone candidate 2.0.0 (76). Native Picture in Picture now
  survives the scene-background/AVKit-active callback race and observes the
  retained player's time-control state so the system PiP Pause and Play buttons
  remain aligned with Fotty and Now Playing. Four focused PiP regressions, the
  complete simulator-free unit/Release gate and ten selected Catalyst UI checks
  pass. One signed optimized Release app installed in place and launched only on
  Jelani's iPhone; TestFlight build 75 and every other device are unchanged.
  Hands-on testing rejected build 76: its PiP window still could not resume a
  native cricket stream while Fotty was backgrounded. TestFlight build 75 is
  still the shared fallback; build 76 must not be promoted.

## [2.0.0 (75)] - 2026-09-06 - fixture freshness and daily-use internal beta

- Promote the complete private reliability batch after build 55: personalised
  three-day Home, audience-led live ordering, catalog performance work, one-tap
  cricket discovery, playback lifecycle/controls, connected Matchday journeys,
  current FPL workspaces and honest recovery states.
- Deploy the fixture-freshness Worker from clean ancestry, publish the protected
  daily CPL/PL/CL/provider monitor, and verify 39 CPL, 380 Premier League and 144
  Champions League fixtures in production.
- Pass the live provider audits, complete simulator-free native gate, generic
  Release compile and signed Xcode 26.6 archive. Apple accepted and processed
  the internal-only upload; established encryption compliance and focused notes
  are saved, and build 75 is Testing for the existing seven-person
  `Fotty Internal Smoke` group. See `docs/releases/Fotty-2.0.0-75.md`.

- Harden fixture freshness for CPL, Premier League and Champions League. CPL
  content revisions are now separate from successful verification receipts;
  last-known-good fallbacks cannot masquerade as current or downgrade a verified
  cache. Failed/old schedule checks surface a refresh warning, stale official
  football analysis is removed from authoritative matching, and the daily
  provider monitor now validates complete live PL/CL season feeds. The Worker,
  protected monitor and app behavior are active in internal build 75.

- Allocate private iPad candidate 2.0.0 (74). Personalized Home now presents
  selected live events followed by up to three days of selected fixtures in
  kickoff order, capped at three upcoming rows on iPhone and four on iPad. The
  shared catalog retains the full 72-hour window, while broad Home preserves its
  six-hour feature window, two-row later cap and prior 48-hour later boundary.
  Final simulator-free tests and generic Release pass; the signed optimized
  build installed/launched only on Jet iPad and visually shows the saved-interest
  state plus `Next 3 days`. iPhone 70 and TestFlight 55 are unchanged.

- Allocate private iPad candidate 2.0.0 (73). Home now offers one compact,
  truthful interests entry point and an opt-in `Only show my interests on Home`
  mode backed by the existing favorite-team and competition records. Full lineup
  and Search retain the complete catalog, empty or unavailable preferences fail
  open, competition selection does not enable alerts, and encrypted backups
  remain compatible with older files. The complete simulator-free suite and
  generic Release pass; the signed optimized build installed/launched only on
  Jet iPad and its default broad-Home state is visually present. The owner then
  confirmed PL/UCL/CPL filtering and a relevant one-day fixture on hardware.
  TestFlight 55 and Jelani's iPhone 70 are unchanged.

- Allocate private iPad candidate 2.0.0 (72). Home now reserves its prominent
  live positions for the audience's ranked interests, keeps every other live
  event under a compact counted More live disclosure and preserves the complete
  Full lineup. Exact same-kickoff aliases from the reviewed team catalog merge
  without fuzzy matching, preventing duplicate fixtures from consuming featured
  positions. The complete simulator-free suite and generic Release pass; the
  signed optimized build installed/launched on Jet iPad, the duplicate was
  visually absent, and the normal app survived a 60-second hold. Hands-on
  interaction acceptance remains open; iPhone 70 and TestFlight 55 are unchanged.

- Replace the physically rejected Home scroll path with private optimized
  iPhone build 70. Flatten fixture/date content into one stable lazy sequence,
  remove absolute pixel-offset restoration, precompute score/competition/badge
  presentation, bound normal row geometry, use the shared catalog clock instead
  of per-row timelines, and cache custom row measurements. Full simulator-free
  tests and generic Release pass; the signed app installed/launched and survived
  a process hold on Jelani's iPhone. Hands-on cold-scroll acceptance is pending;
  Jet iPad and TestFlight 55 are unchanged.

- Supersede physically rejected private build 68 with optimized iPhone build
  69. Restrict catalog-wide channel fallback to source-less CPL rows, cancel
  badge loads after their final visible waiter disappears, use a 24-hour badge
  catalog freshness window, parse remote league maps off MainActor and remove
  per-row regex normalization. Full simulator-free tests/Release and signed
  install/launch pass; hands-on cold-scroll acceptance remains pending.

- Allocate private performance candidate 2.0.0 (68) and install its signed,
  optimized Release app on Jelani's iPhone. Global badge refresh no longer
  invalidates every catalog row; requests are coalesced/downsampled in bounded
  caches, Home projections are revision-cached and SwiftData replacement runs
  off MainActor without a catalog-wide animation. Add signposts, bounded
  MetricKit summaries and a self-cleaning physical performance gate. Full
  simulator-free tests and generic Release pass; cold-scroll acceptance remains
  open. Jet iPad and TestFlight 55 are unchanged.

- Allocate private iPhone candidate 2.0.0 (64). A native UIKit toolbar now owns
  Pause/Sources touches above WebKit, and Pause clears the earlier surface tap
  used to reveal controls before enforcing user-paused state. The simulator-free
  gate passes; a decoded Groningen–Twente stream physically held at 76:05,
  Fotty Play and provider Play both resumed, and Sources opened. Jet iPad now
  runs build 64, but its provider-dependent UI runner never reached a player;
  cross-device controls remain a manual gate and TestFlight remains 55.

- Allocate private playback-control candidate 2.0.0 (61), installed from one
  signed artifact on Jelani's iPhone and Jet iPad. Web chrome now remains
  tappable above the provider and an explicit Pause resists scripted provider
  restarts while allowing a genuine provider Play tap. The complete
  simulator-free gate passes; exact-device control acceptance remains pending
  and TestFlight stays on build 55.

- Allocate private candidate 2.0.0 (59), install the same signed app on Jelani's
  iPhone and Jet iPad, launch both, and retain both main app/Live Activity
  processes through a 60-second hold. Signed Release smoke passes; TestFlight
  remains 55 and hands-on acceptance remains open.

- Preserve Home sport/league/cricket/following filters and Home/Search/Matchday
  browsing positions across navigation, without adding another state owner.
- Reflow Settings and the FPL deadline action at accessibility text sizes; let
  Playback Sources inherit Light/Dark/System and keep diagnostics secondary.
- Verify Matchday writes before publishing success, keep failed removals and
  their reminders intact, roll back reminder creation when its save fails, and
  refuse misleading follow edits while SwiftData is using temporary storage.
- Self-check encrypted exports before Files handoff, stop a failed Matchday
  restore before replacing follows, and make feedback preparation distinct from
  confirmed delivery. The simulator-free gate passes 486 tests with two planned
  skips, generic iOS Release, and seven affected Catalyst journeys. UI automation
  now isolates retained Home state between test processes. Batch 4 remains local
  pending the dated physical gates.

- Refresh Rival Race and selected player histories from coherent current FPL
  evidence, retaining labeled previous results on failure without extra pollers.
- Protect season/manager identity, preserve unknown-origin legacy plans/chats,
  bound planners to real gameweeks, qualify chip windows and unify wildcard budget.
- Give journal decisions explicit targets and preserve historical evidence dates.
- Resolve named players before Coach shortlisting, bound follow-up/history work,
  and validate optional complete transfer routes without treating prose as verified.
- Keep factual Coach answers available locally with cloud consent off; distinguish
  raw published GW points from net points after transfer hits exactly once.
- FPL batch remains local pending the documented device/live-model checks.
- Qualify this local batch with 481 passing native tests (two intentional live/
  soak skips), generic unsigned iOS Release, 135 web/Worker tests and Worker
  dry-run. Reused temporary native/packaging output removed after verification.

- Connect Home, Search and saved Matchday to one current Watch action, including
  one-tap reviewed CPL channel alternatives without an extra selection screen.
- Preserve saved/reminded intent through catalog omissions and reschedules;
  distinguish changed starts, checked scores, listed starts and stale coverage.
- Make multisport team identities and Favorite Leagues work consistently across
  onboarding, Following and Matchday, with recoverable isolated migration.
- Collect provider discovery incrementally with fair bounded opportunities;
  preserve partial conflict evidence and stop penalizing unrelated matches for
  one failed stream. Refresh Match Hub score/insights as one owned snapshot.
- This connected-journey batch remains local, with verification and remaining
  device checks in the dated connected-sports implementation record.

- Restrict native media relay access to loopback/session routes, scope credentials
  and redirects, and bound its requests, manifests and lifecycle. DNS preflight is
  not address pinning; real-provider physical qualification remains open.
- Add revocable private Coach access with device-only secure storage, mandatory
  configured limits, one cancellable deadline and a persisted group allowance of
  50 paid attempts per UTC day. New backend configuration stays paid disabled;
  nothing is activated or deployed by these source changes.
- Preserve unfinished manager/season transfer plans with Undo and explicit refresh
  conflicts; validate combined suggestions and final saves against complete squad
  and current budget rules. Backup restore clears replaced working staging.
- Pass the combined simulator-free native unit/iOS Release gate, all 83 web/Worker
  tests and a Worker packaging dry-run. See the dated foundation implementation
  record and product execution roadmap; the full roadmap is not yet complete.

- Replace one-team fuzzy playback admission with strict fixture identity and
  quarantine conflicting provider IDs without duplicate visible rows.
- Own and cancel delayed playback retries across pause, recovery, dismissal,
  source changes, backgrounding and network transitions.
- Bind web playback/native handoff to visible main-player media and eligible
  parent frames; preserve background resume and reject unrelated ad/resource evidence.
- Retain distinct same-language, HD/SD, URL-query and required-header delivery
  alternatives under the existing bounded discovery limits.
- Refresh coherent FPL gameweek/fixtures/published-picks/live snapshots across
  deadlines and full time, with complete-snapshot retention and age-aware stale labels.
- Add controlled lifecycle/identity/media/FPL regressions. These local changes
  are not included in installed build 58 or TestFlight 55; see the dated reliability audit.

## [2.0.0 (58)] - 2026-09-04 - private direct Score808 candidate

- Replace unverified cross-provider ID guessing with the actual site's published
  team/kickoff/Watch mapping, bounded trusted-page reads and configured-player checks.
- Keep the provider's player context and controls while fitting it to Fotty's
  viewport; exclude unrelated ad media from this route's playback/handoff ownership.
- Resolve the direct site alongside shared providers, retaining already-found
  choices and actionable failures. Report discovery deadlines truthfully.
- Add adversarial matching, transport, cancellation and media-ownership tests;
  the opt-in real-site discovery check passes. See the build-58 record for gates
  and physical acceptance status. No TestFlight upload is included.

## [2.0.0 (57)] - 2026-09-04 - private late Score808 discovery candidate

Historical candidate, not an accepted fix: its donor and stub-rejection claims
below were disproved by the follow-up direct-site investigation and superseded
in build 58.

- Treat Score808 as a late-availability provider: an explicit Watch tap within
  30 minutes of football kickoff refreshes catalog metadata even when another
  source was already cached.
- When that refreshed catalog still omits Score808, probe one verified
  `admin`-identity `hotel` route and expose it only after normal player-page
  validation succeeds. Do not advertise it early or retain an empty stub.
- Pass the complete simulator-free Catalyst unit and generic iOS Release gate,
  then install and launch the signed build only on Jet iPad. TestFlight remains
  build 55.

## [2.0.0 (56)] - 2026-09-04 - private provider trust diagnostics candidate

- Preserve provider certificate/trust failures when every advertised embed
  fails, and explain that Fotty cannot open the provider safely instead of
  claiming that no stream exists.
- Surface the resolver's real failure message consistently from Home,
  Matchday and Match Hub. Apple networking's `NSURLErrorDomain -1202` form is
  covered alongside native `URLError` values.
- Pass the complete simulator-free Catalyst unit and generic iOS Release gate,
  then install the separately signed build only on Jet iPad. CoreDevice reports
  Fotty Sports Hub 2.0.0 (56) with both the app and Live Activity extension
  running. TestFlight remains build 55.

## [2.0.0 (55)] - 2026-09-03 - internal Fotty Sports Hub identity release

- Rename the public-facing product to **Fotty Sports Hub** so the name matches
  the app's football, cricket, basketball, baseball, hockey, tennis and other
  sports coverage. Keep the established `FOTTY` wordmark and accepted F/pitch
  icon as the primary visual identity.
- Show `SPORTS HUB` in the Home masthead, use the full product name for the
  installed app, extension, Settings version identity, web install manifest and
  primary web metadata, while retaining natural short-form `Fotty` references.
- Preserve bundle IDs, target/scheme/module names, `fotty://` deep links,
  storage keys, `.fottybackup` compatibility, backend names and signing. This
  is a user-facing rename, not a data or application-identity migration.
- Web/Worker units pass 71/71, lint is clean, the production web build passes,
  and the complete simulator-free Catalyst unit/generic iOS Release gate
  passes. The current three-feed identity audit and signed Xcode 26.6 archive
  also pass. Apple processed the internal-only upload, saved compliance and
  focused testing notes, and shows build 55 as Internal / Testing for only
  `Fotty Internal Smoke`. See `docs/releases/Fotty-2.0.0-55.md`.
- Send an owner-approved Fotty-only App Store Connect invitation to
  `jhamol61@gmail.com` with the Marketing role and no Create Apps permission.
  Internal group membership remains unchanged until the invitation is accepted.

## [2.0.0 (54)] - 2026-09-03 - internal one-tap CPL release

- Promote the owner-accepted build-53 CPL discovery and one-tap channel route
  to internal TestFlight without changing its truth boundary: trusted started
  fixtures say `On now · listed start`, exact match sources stay preferred,
  Fox is the one-tap fallback and Willow remains a separate channel row.
- The current catalog/live-identity gate, Xcode 26.6 signed archive, matching
  app/extension metadata and strict signature verification pass. Apple accepted
  and processed the internal-only upload; the existing `Fotty Internal Smoke`
  group and focused English (U.K.) notes are assigned. See
  `docs/releases/Fotty-2.0.0-54.md`.
- Send Fotty-only App Store Connect invitations to two owner-selected accounts
  with the qualifying Marketing role. They remain pending until accepted and
  cannot be added to the internal TestFlight group yet.

## [2.0.0 (53)] - 2026-09-03 - private one-tap CPL candidate

- Count a started trusted CPL fixture as `On now · listed start` even when its
  exact match source is absent, fixing Cricket incorrectly advertising tomorrow
  during a current match. Generic source-less and unknown-time events remain
  excluded.
- Remove build 52's extra channel-selection sheet. One tap on a source-less
  current CPL fixture now opens the preferred active Fox Cricket channel; Willow
  remains in the ordinary channel list for manual use. Exact match sources still
  take priority, and Fotty does not claim independent programme confirmation.
- Full simulator-free unit/policy and generic Release gates pass. The signed
  build is installed only on Jelani's iPhone; CoreDevice reports 2.0.0 (53) with
  the normal app running. During the current CPL match, the owner confirmed the
  corrected on-now label and one-tap broadcast route with no intermediate sheet.
  TestFlight remains build 51. See
  `docs/releases/Fotty-2.0.0-53.md`.

## [2.0.0 (52)] - 2026-09-03 - private CPL channel-options candidate

- Keep exact team-and-kickoff sources as the preferred CPL Watch path, but stop
  source-less current fixtures dead-ending while playable Fox Cricket or Willow
  Cricket rows exist elsewhere in the same catalog. Home, the full schedule and
  Search now offer a clearly labelled channel-options sheet during the match
  window. It warns that channel programming is unconfirmed and never silently
  attaches or substitutes a generic channel for a fixture.
- The complete simulator-free policy/Release gate passes. A separately signed
  build is installed only on Jelani's iPhone, where CoreDevice reports 2.0.0
  (52), launches the normal app and observes it for 60 seconds. TestFlight stays
  at build 51; physical CPL option/playback acceptance remains required. See
  `docs/releases/Fotty-2.0.0-52.md`.
- Superseded immediately by private build 53 after physical use showed two
  unacceptable UX gaps: Cricket still said tomorrow during the current match,
  and opening that match required a second channel-selection tap.

## [2.0.0 (51)] - 2026-09-03 - internal TestFlight reliability candidate

- Replace the manually refreshed CPL-only snapshot path with a validated remote
  manifest, last-known-good device cache and daily fail-closed official/current
  source monitor that prepares schedule changes for review. A partial or
  conflicting source cannot overwrite the app's trusted fixtures.
- Stop completed CPL T20 rows lingering into the following day: the continuity
  allowance is now eight hours after listed start instead of 36 hours. Preserve
  CPL's official 10:00 a.m. Guyana time for Match 28 despite a current verifier's
  five-hour discrepancy. See
  `docs/audit/Fotty-CPL-Fixture-Reliability-2026-09-03.md`.
- Deploy Worker source `2026-09-03.cpl-fixtures-3` as Cloudflare version
  `2b988894-e84a-45ac-b60f-23e2a8eac498`; production health and the public CPL
  route return the expected source identity, 39 fixtures and official Match 28
  start. Merge protected PR #16 after repository, web, iOS and CodeQL gates pass,
  then prove the published daily monitor through a successful manual run.
- Install the complete milestone directly on Jelani's iPhone 15 Pro Max as
  2.0.0 (51). CoreDevice independently verifies the version, normal launch and a
  60-second process hold. A fresh Xcode 26.6 archive then passes matching
  app/extension versions and strict signing; Apple's internal-only upload is
  accepted at 18:07 AST. Processing and the prior built-in-encryption-only
  declaration complete. The owner-approved testing notes are saved, only Fotty
  Internal Smoke is assigned, and App Store Connect independently shows build 51
  **Internal / Testing**. The group now has three testers and eight builds; the
  already-qualified Marketing account `kevon.samuel32@gmail.com` was added and
  is **Invited**, without broadening its permissions. No simulator, iPad install
  or connected-phone change occurs during the TestFlight release. See
  `docs/releases/Fotty-2.0.0-51.md`.

## [2.0.0 (50)] - 2026-09-01 - private iPhone 16e Graphify candidate

- Continue the Graphify hotspot phase by extracting deterministic playback failure/source policy while retaining one `LivePlayerViewModel` owner for AVPlayer, WebKit, proxy, attempt, task and PiP lifecycle. Preserve same-attempt network recovery, same-source native return, bounded web retries and failover order; remove the unused duplicate source selector/logger/imports. Focused playback contracts and the complete simulator-free native gate pass.
- Begin the Graphify hotspot phase by extracting manager-scoped FPL workspace persistence and pure derived decision-state computation from `FPLAdvisorViewModel` without changing its observable API or creating another state owner. Remove duplicate full-load/live-refresh recomputation; focused FPL trust tests and the complete simulator-free native gate pass.
- Complete a Graphify-led dead-code and optimization milestone. The supported graph drops from 464 to 380 scanned code files, 6,437 to 5,769 nodes, 16,886 to 15,005 edges and 291 to 250 communities, with no import cycles before or after.
- Physically remove the retired TWA/Android and homelab roots, Hybrid P2P/Ace/warmup implementation, disconnected v1 web UI, duplicate web playback/session/token stack, dead module APIs and obsolete one-off provider research scripts. Preserve only explicit unsafe-source rejection and installed-schema compatibility boundaries.
- Final simulator-free iOS unit/Release, clean web lint, 66/66 web/Worker units, production Next build and Worker dry-run pass. No version bump, install, TestFlight upload, deployment or publication is included. See `docs/audit/Fotty-Graphify-Dead-Code-and-Optimization-2026-08-31.md`.
- Approved reliability-first next phase: fresh tester evidence, data/Coach confidence, compatibility/recovery, then measured personalization/operating decisions and branding. See `docs/NEXT-PHASE-PLAN.md`; this is not a claim that every phase is implemented.
- Adopt the whole-app qualification direction: make discovery/playback the universal promise, retain FPL as an optional first-class workspace, keep Gameweek/Squad/Coach primary, and label every secondary FPL tool by evidence maturity.
- Remove unreachable social/chat/profile, old insights/highlights, mock-match, stream-debug and validation surfaces. Remove the unused avatar/photo UI and photo-library permission while retaining old SwiftData type metadata only for installed-store compatibility.
- Warn visibly when persistent storage falls back to a non-saving in-memory session. Reconcile the Apple privacy manifest to public FPL ID, installation ID and opt-in Coach content using the current manifest schema.
- Add a non-secret Worker `sourceVersion` health field for future deployment verification and define a 3–5 tester, seven-day private qualification with the iOS/iPadOS 26.4 minimum retained for this cycle. These changes are local: no Worker deployment, device install or TestFlight upload is included.
- Allocate build 50 because private build 49 was already consumed before these source changes. Pair and register only the connected physical iPhone 16e, then install the strictly signed app with matching 2.0.0 (50) Live Activity extension. CoreDevice independently reports build 50, launches the normal app and observes a 60-second process hold. This is private installation evidence only; TestFlight remains build 48 and no other device, tester or service changed. See `docs/releases/Fotty-2.0.0-50.md`.

## [2.0.0 (49)] - 2026-08-31 - private iPhone badge reliability candidate

- Repair the corrupted live-provider badge-token URL used by build 48. The corrected endpoint returns valid image data for all 164 unique football, baseball and basketball badge tokens in the current 297-event feed.
- Publish completed league catalogs incrementally instead of blocking valid ESPN results behind an optional slow provider, retry a failed cold bootstrap after a bounded cooldown, and try known team artwork when an explicit provider image fails.
- Expand exact fallback coverage for the current live catalog: 144/144 empty-provider football names, 30/30 MLB names, 52/52 American-football names and 16/16 rugby names. Ambiguous rugby shorthand such as Bulldogs and Broncos stays scoped to rugby rather than cross-wiring another sport.
- Focused regressions and the full simulator-free native gate pass. At the owner's request, the shared archive was interrupted before completion and the upload phase never ran. A separately built signed Debug artifact was installed in place only on Jelani's iPhone, where CoreDevice reports 2.0.0 (49) and a normal launch. Build 48 remains the newest TestFlight build. Small corrections now use this private pre-test lane; TestFlight waits for a meaningful multi-day milestone batch.

## [2.0.0 (48)] - 2026-08-31 - premium identity, motion and recovery

- Complete the six-step premium identity and motion plan: audit every reachable team badge, repair shared football aliases and major basketball/baseball/hockey/cricket coverage, add stable monogram fallbacks, and give Football, Cricket and Tennis distinct contextual loading motion that respects Reduce Motion. The live badge audit resolves all 272 referenced image URLs and rejects suspicious identity collisions; no runtime badge-scraping dependency is introduced. See `docs/audit/Fotty-Badge-and-Sport-Motion-Audit-2026-08-31.md`.
- Add an explicit local-only private backup flow under Settings → Privacy so the owner can export and restore Fotty preferences and manager-scoped planning data through the system Files picker. The format is versioned and validated before import; it does not upload data or create a cloud account. See `docs/audit/Fotty-Private-Product-Recovery-2026-08-30.md`.
- Installed the merged native PiP background-continuity correction and current Home search/football-identity pipeline only on Jet iPad as private build 47. The signed app and Live Activity extension both report 2.0.0 (47); CoreDevice independently confirms installation and a 60-second foreground process hold passes. This uniquely numbered direct Debug candidate is not TestFlight build 46 and does not certify PiP until a real native stream survives another app for 60 seconds plus lock/unlock without source replacement or duplicate audio. See `docs/releases/Fotty-2.0.0-47.md`.
- Replace symptom-level football league filtering with one generated Swift/TypeScript club resolver, kickoff-bounded official-fixture competition reconciliation, redacted on-device identity diagnostics, shared provider payload regressions and a fail-closed live metadata drift gate. Exact Chelsea–Brighton and newly exposed Deportivo/Bundesliga 2 variants pass across all three reachable feeds; full native policy and generic iOS Release gates plus 87 web/Worker tests pass. This pipeline is installed only on Jet iPad in private build 47; physical discovery/league-placement acceptance and shared TestFlight distribution remain outstanding. See `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md` and `docs/releases/Fotty-2.0.0-47.md`.
- Apple accepted the internal-only build-48 upload at 12:03:54 AST. Processing, the built-in-encryption declaration and testing notes completed; App Store Connect independently shows **Internal / Testing** for only the existing Fotty Internal Smoke group with two invitations. Exact TestFlight installation and physical iPhone/iPad acceptance remain outstanding. See `docs/releases/Fotty-2.0.0-48.md`.

## [2.0.0 (46)] - 2026-08-30 - single product graph correction

- Remove the alternate review-safe app graph, StoreKit distribution unlock, compile-time substitutions and misleading sports aliases. Fotty now has one truthful product path across Debug, Release and TestFlight; football remains Football, normal league names remain visible, and playback/discovery no longer depend on an asynchronous launch entitlement.
- Exact-source Catalyst units pass 219 with one existing opt-in skip; the vocabulary/retired-symbol gates and normal iOS Release compile pass. The Home UI runner timed out enabling beta-Mac automation twice before execution, so physical TestFlight acceptance remains required.
- Xcode uploaded the signed internal-only archive successfully at approximately 17:56 AST on 2026-08-29. Apple completed processing; the owner approved and saved compliance, testing notes and only the existing Fotty Internal Smoke group. At 09:14 AST on 2026-08-30, Apple independently shows **Internal / Testing** with two testers. See `docs/releases/Fotty-2.0.0-46.md`.
- A direct read confirms TestFlight build 46 is installed on the iPad. The iPhone still reports build 44 after TestFlight was reopened, so its update remains pending and no two-device physical acceptance is claimed. The temporary archive/build/log output is removed and 53 GiB is free.

## [2.0.0 (45)] - 2026-08-29 — data and platform safety round

- Consolidate build 44's published-squad/local-draft separation into the shared beta. Official FPL scoring remains independent of hypothetical edits, rejected replacements stay visible, and public deadline publication is explained honestly.
- Scope pending Coach replies to their conversation, manager, gameweek and planning context. Clearing, disabling or disconnecting invalidates late work without an automatic paid retry; deterministic score questions retain published-evidence and freshness checks.
- Generate current 2026/27 football competition membership from one reviewed source for iOS and web. Domestic inference requires both current senior clubs and rejects cup, youth, friendly and lower-division conflicts; stale reference data now fails the release check.
- Version and bound FPL caches by season, endpoint age and catalog fingerprint; prevent an empty requested schedule window from borrowing older fixtures. Reconcile privacy disclosures with active local storage, public FPL lookup, opt-in Coach processing and third-party playback.
- Replace App Store receipt-filename detection with StoreKit-verified `AppTransaction` environments. Verified TestFlight sandbox/Xcode builds receive internal access; production, unverified and failed checks start and remain review-safe. The grant is process-local and retried on foreground activation.
- Remove obsolete bitcode configuration. The companion web toolchain is modernized and vulnerability-free locally, but no website or Worker deployment is part of this TestFlight build.
- Xcode uploaded the signed internal-only archive successfully at 15:15 AST. Apple completed processing; the owner saved the matching encryption declaration and explicitly approved the testing notes plus existing-group assignment. At 15:21 AST, Apple independently shows **Internal / Testing** for Fotty Internal Smoke with two invitations. See `docs/releases/Fotty-2.0.0-45.md`; no simulator, direct install, external submission, tester/role change, Worker deployment or Git publication.

## [2.0.0 (44)] - 2026-08-28 — private iPhone FPL draft fix

- Preserve saved manager-scoped local squads across official refresh, foreground return and reopening. Keep published picks, gameweek and scoring evidence separate from hypothetical edits.
- Label Published squad / Local draft and retain both when switching views or receiving the next deadline snapshot. Explain why private official-app changes are not visible before publication.
- Keep rejected replacements open with a visible reason; restrict replacements to the outgoing position and do not show transfer success after rejection.
- Keep official autosubs, points and factual Coach answers independent of local drafts; label draft advice and omit invented published/live fields from its evidence packet.
- Phone-first delivery is owner-approved. Verification and exact installation status are recorded in `docs/releases/Fotty-2.0.0-44.md`; no TestFlight upload, Worker deployment or other device update is included.

## [2.0.0 (43)] - 2026-08-28 — internal TestFlight reliability round

- Fix false web-playback stalls after a replacement/reset playhead; scope post-start errors and recovery to the actual video/document while preserving pause and real-stall detection.
- Keep missing/duplicate FPL scoring data unknown, preserve only supported official totals, suppress unproven autosubs/captaincy, and label incomplete data in the app.
- Keep scoring questions deterministic when official evidence is missing or stale; retain DeepSeek for tactical advice. Validate Coach request shapes, bound streaming bodies and fail configured rate-limit outages safely. Worker revision `fafdf5ed-4d37-47e6-82b8-69dd55c3e116` is deployed; production health/request/zero-token scoring checks pass.
- Full 191-unit suite passes with one optional soak skip and no runtime warnings; web/Worker 81/81, production web build, two scoped Catalyst UI checks, Review Safe and normal signed archive pass. UI checks retain two main-thread warnings and one permitted pre-test automation retry.
- Apple accepted the upload at 12:37:49 AST and completed processing. The owner-approved declaration/testing notes/group assignment are saved; Apple independently shows **Internal / Testing** at 12:47 AST for Fotty Internal Smoke. The existing two testers and roles remain unchanged; installation/physical acceptance and received feedback remain open. See `docs/releases/Fotty-2.0.0-43.md`; no direct installs, simulator, external submission or Git publication.
- Unchanged-source iOS 18 normal Release compilation passes diagnostically; distributed minimum remains 26.4 pending older-device qualification. Prepared tester/Coach evaluation ledgers and triage guidance, not fabricated outcomes. Removed the 1.4 GB temporary build tree and separate upload logs; 62 GiB free.
- Physical TestFlight acceptance, reminder delivery/return and one received feedback report remain required before wider invitations.

## [2.0.0 (42)] - 2026-08-28 — internal TestFlight consolidation

- Package the qualified build-41 app as a fresh internal-only release number. Consolidates builds 36–41: all-sports Home, badges/equipment icons, optional Light/System appearance, dedicated FPL, cricket/CPL discovery, provider-control fixes, countdowns, opt-in reminders and compact Watch-right rows with secondary saving.
- Normal signed Release is **Testing** for Fotty Internal Smoke, independently verified at 06:18 AST. Upload and processing are complete, the owner-approved encryption declaration is accepted, six testing tasks are saved, and the same two-tester group is assigned. An expired session was resolved without a rebuild or repeat upload. No new feature code, tester/role changes, direct installs, simulator, external submission or Git publication; fresh build-42 physical acceptance remains separate.
- Reuses exact-source 184-unit/two-scoped-UI evidence; the new archive passes version/signature/production checks. One 314 MB temporary root and 576 KB distribution logs were removed; disk remains 40 GiB free. Release status/evidence: `docs/releases/Fotty-2.0.0-42.md`. Next-step planning is discussion-only.

## [2.0.0 (41)] - 2026-08-27 — compact match actions

- Restore teams/badges on the left and Watch on the right in Home, full-lineup and My Matchday rows. Only genuinely narrow space or accessibility text stacks actions below the information; ordinary live rows no longer reserve a separate controls strip.
- Move Save/Remove from My Matchday to the native long-press menu and accessibility actions. Upcoming countdowns and opt-in reminder controls remain visible. Help and optional first-use guidance explain saving without alerts.
- Keep reminder/error explanations full-width, existing two-minute playback guards and local-notification behavior. No playback-engine, source, API, theme or saved-data change. Qualification is recorded in `docs/releases/Fotty-2.0.0-41.md`; TestFlight remains 35.

## [2.0.0 (40)] - 2026-08-27 — upcoming match readability

- Preserve full-contrast future team names and badges. Physical build-39 testing caught the disabled row button dimming the entire fixture; future content is now plain information, while only its play affordance is timing-gated.
- Retains the approved countdown and opt-in reminder flow. Verification now renders the actual Home fixture row, not just isolated countdown controls. Exact final iPad/build evidence is in `docs/releases/Fotty-2.0.0-40.md`; TestFlight remains 35.

## [2.0.0 (39)] - 2026-08-27 — countdowns and opt-in reminders

- Replace future Open broadcast actions with an inline Starts in countdown. Show seconds in the final five minutes; enable an explicit source-backed play attempt two minutes before the scheduled start. Channels and unknown times do not acquire fabricated countdowns.
- Add opt-in five-minute match reminders that also save the match in My Matchday. Saving alone is silent. Cancel the bell without unsaving; removing the saved match revokes its reminder. Tapping a reminder returns to the saved match without autoplay.
- Keep failed stream lookup feedback inline with Not ready / Retry and never open an empty player. Share timing guards across Home, Matchday, Match Center and MultiView.
- Persist and reconcile stable local notification requests across learned reschedules, cancellations and permission changes; skip overdue triggers, isolate FPL alerts, bound capacity and reject stale async completions. No new API, provider probing or server service.
- Qualification and iPad outcomes: `docs/releases/Fotty-2.0.0-39.md`. TestFlight remains 35.

## [2.0.0 (38)] - 2026-08-27 — iPad layout and Settings follow-up

- Equal-sized sport tiles share measured width/height and two-line title space. iPad shows all sports across width-aware rows without More sports, including Split View. Compact phones retain overflow and selected-sport continuity; a scaled minimum width reduces columns at larger text sizes.
- Replace the floating appearance picker with Settings → Appearance and clear Dark/Light/System choices; remove Engineering from normal Settings, including development builds.
- Complete the existing static NBA/MLB badge fallback and prevent a sparse persisted badge cache from erasing bundled fallback URLs. This fixes the missing baseball crests observed on the physical iPad; no new runtime catalog API is added.
- 155 unit tests pass, one optional soak skipped, no runtime warnings; normal and Review Safe Release plus signed Debug iOS builds pass. Installed only on the owner's iPad and version-verified. Physical Home shows uniform rows and actual Yankees/Astros badges; a 20-second normal launch hold passes. Countdown/availability routing and remaining touch/theme acceptance are separate. TestFlight remains 35.

## [2.0.0 (37)] - 2026-08-27 — iPad appearance and identity candidate

- Restore team badges beside each team in the new Home rows. Reuse existing provider/catalog imagery, fit full artwork and observe cache updates; use named initials only for missing artwork. Channels and unpaired events do not invent team badges.
- Give sport tiles and category menus recognisable football, basketball, baseball, cricket and other equipment icons without removing the compact all-sports layout.
- Add Settings → Preferences → Appearance: Dark (default), Light and System. Adapt app surfaces, text, borders, status colours, actions and FPL sheets; keep pitch artwork and video dark. Preserve navigation and FPL state when appearance changes.
- Inherit build 36's playback fixes. Final-source unit suite passes 148 tests, one optional HLS soak skipped, with explicit light/dark contrast, symbol availability and bounded layout renders. Device/build outcomes and remaining acceptance are recorded in the appearance audit. TestFlight remains build 35.

## [2.0.0 (36)] - 2026-08-27 — iPad diagnostic candidate

- Remove Fotty's competing WebKit tap recognizer. A passive page observer reveals bounded upper-right controls without taking provider taps or covering the lower control bar.
- Keep provider pause/resume and Fotty's Play/Pause state in sync, preserve intentional pauses through recovery/native handoff, and restore paused state if a Play request is rejected. Popup blocking no longer swallows a normal provider control's JavaScript handler.
- Execute the monitor in regression tests, correcting an uninterpolated startup timer missed by syntax-only checks. The full unit suite passes 144 tests with one opt-in soak skipped. Physical centre/lower-left touch acceptance remains open; TestFlight is unchanged at build 35.
- This candidate includes the previously approved all-sports Home and cricket/tab-separation changes below. The owner requested a normal-app iPad test as an exception to TestFlight-first delivery; no device test helper or simulator is used.

- Home now opens on All sports, with compact activity/next-start summaries, a bounded mixed-sport Now & next list, Later today/Coming up, and See all on Home's own navigation stack. Every sport remains reachable through an activity-aware More sports selector.
- Deduplicate exact event identities for Home counts, keep channels and uncertain timings out of on-now counts, retain dated CPL provenance on All sports, and remove synthetic opponents from non-team event titles. No new API, stream probes or playback-engine changes.
- Light mode has been assessed as a separate app-wide follow-up; this patch retains the current dark theme and does not add an incomplete appearance toggle.
- All-sports Home verification: 140 passing unit tests (one opt-in soak skipped), eight selected Catalyst UI checks, and unsigned normal/Review Safe iOS builds. The separate beta-Mac contrast audit remains unresolved despite passing actual-palette checks; physical-device visual acceptance is still required. Nothing new is uploaded.
- Keep fantasy features in FPL: remove Home/Matchday setup promotion, squad badges, automatic squad-related Matchday entries and the Match Center fantasy panel. Saved matches, followed teams and FPL data/planning remain intact.
- Add Cricket → All cricket / CPL / Channels, with separate Willow/Fox channel rows and persistent channel bookmarks. Channel listings never imply a confirmed CPL programme.
- Add a dated CPL 2026 published-schedule snapshot, including the league's July TKR opponent correction and Barbados Tridents name. It expires after the season, labels its source/date/limits and only takes broadcast sources from an exact team-and-kickoff catalog match.
- Unify Home/card/player timing; use a longer T20 discovery window, avoid inferring a final whistle for unknown cricket formats, and prevent football scores leaking into cricket. No cricket score API or new subscription is introduced.
- The preceding cricket/tab-separation patch was verified locally with 130 passing unit tests (one opt-in soak skipped), five scoped Catalyst UI checks, unsigned normal/Review Safe iOS builds, and sampled advancing Willow CPL playback. The schedule is not live-updated; physical acceptance and a separately recorded TestFlight upload remain. Build 35 remains the distributed version.

## [2.0.0 (35)] - 2026-08-27

- Normal Release is available in internal-only TestFlight: Apple processing and the owner's encryption declaration are complete, tester notes are saved and Fotty Internal Smoke is assigned. App Store Connect reports Testing. This distribution is not fresh physical-device acceptance.
- UI refinement: readable, Dynamic Type-aware FPL text, a large-text squad roster, consistent numbered fixture-difficulty colours, and explicit gameweek/source labels beside points. The normal squad keeps its football pitch.
- FPL retains its loaded manager, workspace, tool and scroll position across root-tab changes without keeping hidden polling views alive. Unsent Coach text, in-progress Coach state, comparison selections and loaded league context survive those changes; manager switching still clears visible context.
- Plan leads with the next decision and uses a two-column decision/evidence layout only when it fits. Tools are grouped by purpose, have a consistent back/title pattern, and comparison uses bounded player/club search. Captain rating and points estimates are explained separately without changing their calculation.
- Home preserves recognizable club names and separates match information from 44-point actions. Future broadcasts say Open broadcast; live matches say Watch live. Matchday removes repeated FPL reasons and groups later fixtures by date. Unknown lineups no longer imply an official announcement state.
- Settings prioritizes football, playback and support over local identity; match updates and scheduled deadline reminders have separate explanations. Feedback fields have persistent required labels and explicit disabled-state guidance. Live Pulse respects Reduce Motion; player/source controls retain existing behaviour with clearer hit regions and dismiss labels.
- Reuses the final-source 122 passing unit tests (one opt-in HLS skip), 14 scoped Catalyst UI checks and normal/ReviewSafe iOS compile evidence. Physical iPhone/iPad qualification through TestFlight remains required before widening the beta.

- Beta usability: Help and Report a problem now work natively without the retired web host. Reports include build/device context, optional previewable diagnostics and explicit copy/share handoff to TestFlight; no automatic submission or false delivery confirmation.
- FPL setup accepts official team links and manager IDs, checks and confirms the retrieved team before selecting it, and keeps retry/change-ID available on failure. Switching clears stale visible state and rejects late responses without deleting saved manager drafts.
- Home has dismissible, optional setup tips; empty Matchday offers Follow a team and Connect FPL directly. Team selection uses Matchday language, adaptive text/layout, bounded search and loading/empty/retry states.
- Inactive navigation tabs now have a full rectangular hit target and expose their selected state to accessibility; the interaction test verifies actual tab selection.
- Match alert settings explicitly describe foreground updates rather than promising background push. Native help explains Premier League score scope, official/provisional FPL totals and local-only draft actions.
- Added beta-usability policy tests, native Help/feedback and first-use navigation checks, and a closed-beta tester guide. Normal updates now use TestFlight instead of direct device installation; source-controlled build numbers must exceed the latest App Store Connect upload.

## Earlier 2.0 beta checkpoints (16–33)

- The release candidate advanced to Apple build 33 after the autonomous form-factor audit added deterministic, network-free large-Type coverage for Matchday, Settings, Match Center, and the Player recovery surface. Catalog-only Match Center resume now preserves its loaded catalog event instead of starting an unnecessary repository refresh; Debug-only surface routes are excluded from Release behavior.
- The release candidate advanced to Apple build 32 after the final autonomous accessibility review added a deterministic, network-free Debug fixture for every FPL workspace. Plan, Squad, Coach, and Tools now run through the release-scope Dynamic Type audit, including a visible structured Coach response and quick-prompt control; Release behavior remains unchanged.
- The release candidate advanced to Apple build 31 after the final widget audit found that the small FPL deadline widget exposed its `Official FPL` source only through accessibility while the medium widget showed it visibly. Small and medium widgets now both present the source on-screen and retain the typed `fotty://fpl` route.
- The release candidate advanced to Apple build 30 after exact build-29 hardware playback reproduced a provider-origin `VPN Recommended / Tap to Install` dialog over an otherwise healthy stream. WebKit now rejects only that matched JavaScript solicitation and removes only matching text/button dialog ancestors that do not own video or iframes; the provider's real unmute control remains untouched.
- The release candidate advanced to Apple build 29 after the exact build-28 Catalyst contrast audit identified Home's empty-feed recovery instruction as too muted at caption size. That actionable guidance now uses primary, medium-weight semantic text, and the audit reports future unignored elements with their label, identifier, type, and frame instead of Apple's generic failure alone.
- The release candidate advanced to Apple build 28 after build-27 hardware verification showed an `AVAILABLE` catalog listing still carrying a `Watch live` action. Only kickoff-window live events now use `Watch live`; upcoming, old, and undated catalog entries use the truthful `Open broadcast` action.
- The release candidate advanced to Apple build 27 after physical build-26 review found upcoming catalog fixtures labeled `LIVE` inside the landscape player and an empty Echo catalog being converted into a fabricated 404 embed. Match Center and player chrome now share kickoff-aware `LIVE`/`UPCOMING`/`AVAILABLE` language, and canonical fallback is limited to source families with a maintained route contract.
- The release candidate advanced to Apple build 26 after physical iPhone review found the new web transport controls centered over the match and permanently visible. Compact controls now sit at the video edge, auto-hide four seconds after playback begins, and return through a non-blocking surface tap; paused playback keeps its Play action visible.
- The release candidate advanced to Apple build 25 after physical playback found a provider embed with working video/audio but no usable transport controls, plus an older same-team league fixture leaking `FT` and its score into a current cup broadcast. Web broadcasts now expose Fotty-labeled Play/Pause controls that command the provider frame tree, while player scores require both team and kickoff identity.
- The release candidate advanced to Apple build 24 after a physical cold-launch deep link to a provider-only live match exposed a dead Match Center. Catalog route IDs now resolve exactly before fuzzy team-name matching; provider-only Match Center presents a truthful broadcast listing and can open playback without fabricating scores, lineups, or statistics. Notification and Live Activity return links therefore remain useful even when no schedule fixture payload exists.
- The release candidate advanced to Apple build 23 after physical review on an iPhone 15 Pro Max using the system Zoomed/Larger Text canvas found the compact Squad pitch too vertically magnified. Narrow iPhones now use one labeled decision toolbar, smaller shirts/nameplates, tighter formation rows, and a shorter pitch so the starting XI remains readable without global view scaling; regular-width iPad layout is unchanged.
- The release candidate advanced to Apple build 22 with a bounded Debug normal-app `--fotty-fpl-workspace` launch argument for Plan, Squad, Coach, or Tools. This enables repeatable physical screenshots through CoreDevice without a simulator, synthetic touch automation, or a device UI-test runner; Release builds ignore the QA-only route entirely.
- The Catalyst accessibility runner retries only Xcode's pre-test `Timed out while enabling automation mode` harness failure once. Real Fotty test failures remain immediate failures, avoiding both false release failures and indiscriminate test retries.
- The physical release gate now builds one signed universal Debug artifact, verifies its strict code-signature seal, and installs that exact bundle on every requested device. This prevents device-specific asset thinning in a shared DerivedData product from invalidating the cached bundle seal; deployment also uses the reliable explicit normal-process termination path instead of CoreDevice's inconsistent `--terminate-existing` option.
- The release candidate advanced to Apple build 21 after build-20 physical iPhone Squad review found its five-player row expanding the entire compact page. Compact shirts, nameplates, and formation spacing now fit within the iPhone viewport without clipping the shared header or controls.
- The release candidate advanced to Apple build 20 after physical iPad FPL review found the three command-centre metrics packed into narrow adaptive columns. They now distribute across the full row, preserving the complete Captain detail on regular-width devices.
- The release candidate advanced to Apple build 19 after the build-18 device recheck proved the hero's remaining false score notice came from a team-name league guess when no schedule fixture matched. Home rows, the hero, and native activity status now require confirmed covered schedule identity before showing any missing-score message.
- The release candidate advanced to Apple build 18 after the build-17 physical iPad Home audit exposed `Premier League 2` as `LIVE · SCORE UNAVAILABLE`. Score coverage name fallbacks now use an explicit senior-competition allowlist, so youth/cup competitions retain a truthful plain `LIVE` state without implying Fotty promised their scores.
- The release candidate advanced to Apple build 17 after physical iPhone playback showed an opaque provider error being exported as an `unknown` terminal boundary. Deferred non-explicit provider errors now become a truthful startup timeout only after the complete 20-second negotiation window; explicit provider-unavailable signals remain unchanged.
- The release candidate advanced to Apple build 16 after physical compact-Home review found two final presentation/eligibility defects.
- Build 16 passed a 60-second physical iPad foreground hold plus unclipped Home/FPL regular-width review; the physical launch gate now retries brief CoreDevice availability flaps and avoids its unreliable `--terminate-existing` path.

## [2.0.0] - 2026-08-24

### Added

- A benchmark-backed product contract for five complete journeys: match discovery, stable playback, deadline planning, live FPL, and post-gameweek review.
- Privacy-safe on-device quality records and a redacted JSON export covering playback, fixture identity, football/FPL freshness, and Coach outcomes.
- Canonical fixture identities and provider aliases shared by the catalog, schedule, score, Matchday, Match Center, notification, FPL context, and playback routes.
- FPL squad decision lenses for fixture, modeled points, expected minutes, form, ownership, price movement, and live points with source, confidence, assumptions, and model version.
- Week-by-week Roll, one-move, and two-move planning routes with hit cost, break-even, downside, checks, validation, and manager-scoped named scenarios.
- A carried Decision Journal lesson in the next planning cycle, plus useful confirmed-gameweek review facts.
- Typed notification, widget, Match Center, and surviving-player deep links.
- A decoded-playback audit with an optional post-start continuity hold, media-time advancement, longest-freeze, final-state, request-failure, and popup evidence.
- A lock-guarded Mac Catalyst runner for the six release accessibility audits plus rapid-navigation check, executed individually without a simulator or physical-device UI-test runner.
- A physical-only, lock-aware normal-app launch/foreground-hold gate that rejects simulator targets and never installs a device UI-test runner.

### Changed

- Smart Coach now answers directly computable points, automatic-substitution, captain, deadline, free-transfer, squad-rule, and selling-price-limit questions with the local rules path and zero model tokens.
- Model Coach requests use a minimized evidence packet, bounded history and tokens, freshness validation, structured evidence/downside/checks, contradiction rejection, returned usage, and deterministic fallback.
- Live Points separates official current, provisional rules, and checked-final states; captain-only vice promotion, legal autosubs, Bench Boost, transfer hits, blanks, doubles, and official substitutions use deterministic Swift and Worker rules.
- Web playback keeps a selected attempt through network recovery and native-handoff failure, allows the full startup window plus one same-source retry, and reports typed app/network/provider boundaries.
- Live Activities show useful match state only when native background/PiP continuity is real; alerts and widgets route to typed destinations with consistent spoiler protection.
- Compact iPhone Squad and Coach layouts use adaptive rows and semantic controls instead of global scaling.
- Cross-origin web broadcasts remain on the selected feed after their frame loads; Fotty no longer invents decoded playback or auto-fails over merely because browser isolation hides the provider playhead.

### Fixed

- MultiView no longer appears merely because two far-future catalog rows have sources; it requires live timing or kickoff within 30 minutes plus the existing recent-decoded-provider requirement.
- Dense Home rows use recognizable club names such as `Leicester` and `Sheff Wed` instead of ambiguous initial-only forms such as `L. City`.
- Dashboard sport/competition filters now expose native menu-picker semantics and selected values; match rows expose useful VoiceOver team labels without duplicate decorative crest announcements.
- FPL loading feedback is one useful accessibility announcement, and Dashboard typography/contrast now clears the six-category Catalyst accessibility gate at standard and large Dynamic Type.
- Premier League single-league/date API-Football fallback requests now use the credentialed Worker boundary instead of failing locally as unauthorized.
- Captain-only provisional promotion now changes the displayed total even when no bench substitution is available.
- Notification and playback routes now resolve canonical, raw, and provider-prefixed fixture aliases to the same match.
- Canonical fallback source synthesis creates one honest choice per provider family rather than inventing duplicate broadcasts.
- Non-football web events no longer show fabricated wall-clock minute labels such as `115′` for baseball or basketball.
- Web watch removes the provider new-tab escape, hides PiP until a native video actually exists, and gives numbered broadcast controls concise selected-state labels.
- A single provider-frame error now advances at most one backup instead of firing two failover callbacks and skipping a usable broadcast.
- The decoded-provider audit no longer forces the catalog-page referrer onto HLS requests, which had created false CDN 403 failures in the test harness.
- Compact web glance chips use meaningful sport names instead of ambiguous three-letter truncations such as `Bas`.
- Live Activity return links now reveal a surviving player or open that match's Match Center after a cold relaunch instead of merely opening Fotty's last tab.
- Live Activities now begin only after AVKit confirms PiP is active; temporary inactive scenes no longer force PiP, and PiP stop/failure/availability loss clears continuity and pauses background playback.
- Web embeds pause their media frame tree when Fotty backgrounds and resume the same attempt on return, preventing provider/ad audio from surviving invisibly behind the app.
- The system toggle-play/pause command now actually toggles playback, and stale lock-screen commands are disabled when the player closes.
- Web player timeout copy now reports the actual 20-second startup window.

### Removed

- The unreachable second Match Center with its obsolete Arena/Highlights tabs and controls.
- Unreachable Dashboard chat presentation and unused legacy For You/P2P card paths whose controls were never part of the active Home or Matchday journey.
- The legacy Hybrid P2P resolver from the production compilation path; active Watch resolution is explicitly limited to enabled StreamEx/Score808 web families.

- Validate the 1.7 audio, playback-recovery, Picture in Picture, and Live Activity paths during active Premier League fixtures.

## [1.8.4] - 2026-08-24

### Fixed

- Smart Coach current-points and automatic-substitution questions now bypass DeepSeek and use a deterministic FPL rules engine over refreshed official picks, live points, minutes, fixture completion, bench order, formation constraints, captain fallback, and transfer cost.
- Live Points distinguishes the official current total from a formation-safe provisional automatic-substitution total, shows an explicit `Before autosubs → After autosubs` point change, names the incoming and outgoing players, and switches back to official labeling when FPL publishes its substitutions or completes the data check.
- Coach evidence now includes squad position, outfield bench order, published/effective multipliers, live minutes and points, fixture state, and the authoritative scoring status; the local fallback uses the same resolved live summary.

### Changed

- Deterministic scoring answers use zero DeepSeek tokens and identify `Fotty FPL Rules Engine` as their source instead of presenting model inference as an official total.

## [1.8.3] - 2026-08-24

### Fixed

- The FPL workspace now uses tighter compact-width spacing, cards, and navigation on iPhone, removes the duplicate title above Smart Coach, and no longer reserves obsolete space above the persistent tab bar.
- Sending a Smart Coach question with the send button or Return key, and selecting a quick prompt, now dismisses the keyboard so the reply remains visible; the conversation also supports interactive keyboard dismissal.

## [1.8.2] - 2026-08-24

### Added

- A Rival Race Centre built from published squads, official standings, current fixtures, and official event-live points, with captain comparison, unique-player swing, shared players, and players remaining.
- Structured Smart Coach cards that separate the recommendation, confidence, checked evidence, downside, deadline checklist, source, model, and official-data freshness.
- A Transfer Lab that compares roll, one-transfer, and two-transfer routes with estimated cost, modeled net gain, downside, validation checks, and local staging.
- A manager-and-season-scoped Decision Journal for recording calls before the deadline and reviewing the reasoning after the gameweek.
- A small and medium FPL deadline widget with a system-managed hourly official-data refresh and direct navigation back to Fotty's FPL workspace.

### Changed

- FPL Tools now has clear destinations for Transfer Lab, Rival Race, and the Decision Journal, with larger semantic hit targets and less decorative or ambiguous UI.
- Mini-league rows now make rival selection explicit and exclude the current manager.

## [1.8.1] - 2026-08-24

### Fixed

- My Matchday's header now truthfully describes saved, followed-team, and FPL-relevant fixtures instead of omitting the new FPL source.

## [1.8.0] - 2026-08-24

### Added

- A phase-aware FPL gameweek snapshot that changes its headline metrics and primary workspace between planning, locked, live, and review states.
- Device-local FPL squad context on Home match cards, including starter, bench, and captain involvement without adding background API calls.
- An FPL Match Lens in Match Center that shows the user's involved players and official live points/minutes when already available.
- FPL squad fixtures automatically join the personal Matchday plan alongside saved matches and followed teams.

### Changed

- Renamed the ambiguous `Matches` destination to `Matchday`; its persisted tab identity remains compatible with existing installs.
- The FPL gameweek workspace is labeled `Plan`, `Live`, or `Review` according to the verified gameweek phase.
- Version tooling now keeps `project.yml` synchronized with every Xcode target so regenerated projects cannot silently reset the release version.

## [1.7.2] - 2026-08-24

### Fixed

- Home `Match schedule` now contains only live and upcoming fixtures.
- Completed saved or followed fixtures remain available briefly under `Matches → My Matchday → Recent` instead of appearing in Home as scheduled content.

## [1.7.1] - 2026-08-24

### Fixed

- Restored direct interaction with provider play, pause, seek, fullscreen, and mute controls by removing Fotty's full-player web tap gesture.
- Removed Fotty's duplicate `Tap to unmute` button and stopped reapplying a forced mute state every 500 milliseconds in the standard player.
- Provider `Tap to unmute` prompts now own their intended direct WebKit user gesture; Fotty continues to observe playback and contain popups without removing or replacing legitimate controls.

## [1.7.0] - 2026-08-24

### Added

- My Matchday as a saved-and-followed fixture workspace distinct from Home discovery.
- Premier League live scores using official public FPL fixtures with bounded fallbacks.
- Official-data-first FPL planning, live tracking, squad validation, and Smart Coach evidence.
- Native-handoff support when a decoded web player exposes a verifiable HLS or MP4 stream.
- Language and broadcaster details for catalog source choices when available.

### Changed

- Reworked Home, Match Center, FPL, Settings, and the persistent navigation into the Matchday Editorial baseline.
- Web broadcasts now receive a 20-second startup window and one same-source retry before failover.
- Broadcast choices collapse HD/SD duplicates and no longer mix invented empty-family rows with real variants.
- Live Activities are limited to playback states that can honestly continue outside the foreground app.
- Settings displays the full app version and build number.

### Fixed

- Blocked observed popup-ad frames and click-through chains without removing player controls.
- Made Fotty's Tap to unmute control apply to main-frame, child-frame, and newly created media players.
- Preserved the current decoded source through short stalls, network transitions, and stale delayed callbacks.
- Unified Home and My Matchday catalog ownership to prevent contradictory fixture states.

### Removed

- Retired PocketBase/cloud-account claims, homelab P2P/AceStream product paths, EPG/TV Guide surfaces, and World Cup-specific product UI.

[Unreleased]: https://github.com/jetboss/Fotty/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/jetboss/Fotty/compare/v1.8.4...v2.0.0
[1.8.4]: https://github.com/jetboss/Fotty/compare/v1.8.3...v1.8.4
[1.8.3]: https://github.com/jetboss/Fotty/compare/v1.8.2...v1.8.3
[1.8.2]: https://github.com/jetboss/Fotty/compare/v1.8.1...v1.8.2
[1.8.1]: https://github.com/jetboss/Fotty/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/jetboss/Fotty/compare/v1.7.2...v1.8.0
[1.7.2]: https://github.com/jetboss/Fotty/compare/v1.7.1...v1.7.2
[1.7.1]: https://github.com/jetboss/Fotty/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/jetboss/Fotty/releases/tag/v1.7.0
