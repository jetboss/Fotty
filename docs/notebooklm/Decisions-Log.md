## 2026-11-11: Link Fox Cricket's guide to the T10; restore the WBBL Fox link (Worker deployed, app on Jet 279)

Fox changed its guide format: the WBBL episode line now reads "S2024 , Ep14 , Stars v Heat", which silently stopped every live WBBL Fox link. It titles the T10 "Live: Abu Dhabi T10 League: Aces v Lions" and cuts long titles at 40 characters. A Fox listing now resolves when its episode line carries a known pair (optionally after season/episode) and the title is an exact leading part of "Live: <competition>: A v B". A Fox T10 programme links only to the unique, fresh, live ESPN T10 fixture of the same pair (3-hour window, no ordinal). The app (d957658) accepts T10 Fox links, and media still comes only from the user's enabled AU Fox Cricket channel source. Worker abec37e deployed as `2026-11-11.fox-t10-1` (cec50591) from a clean copy (529 tests); app suites pass (253). Live registry at 15:11 UTC: Fox programme listed for Royal Desert Champions v UAE Bulls. Jet 279 installed (60 s hold); the owner confirmed the match returned as the Live now hero with Watch. T10 badges stay as monograms: ESPN's cricket logo URLs return 404 and TheSportsDB has no entries.

## 2026-11-11: Carry the Abu Dhabi T10 (Worker deployed)

Owner approved. Fox Cricket and Willow showed a live Abu Dhabi T10 match that Fotty did not list, because no cricket schedule covered the league. A new isolated cohort reads ESPN's public scoreboard (league 18522) by month: ESPN event and team IDs, match numbers, and the feed's live, finished or abandoned state. TBA play-offs are skipped until named. It is season-gated to November 2026 behind `CRICKET_T10_ENABLED`, and a failure keeps accepted rows without touching ICC, CPL or WBBL. The app already accepts any cricket competition and the T10 format, so no app update is needed. Commit 7ce6ded, deployed as `2026-11-11.abu-dhabi-t10-1` (ab9af64b) from a clean copy of HEAD; the other session's uncommitted Worker edits stayed undeployed. The live feed showed 20 T10 fixtures at 14:35 UTC, with match 11 live. Jet 278 picked it up at its next 5-minute cricket refresh (14:38 UTC), with no app change, and the owner confirmed the match shows on Jet. Not done: linking Fox Cricket and Willow programmes to T10 fixtures.

## 2026-11-11: Internal TestFlight 3.0.0 (278): broadcast registry fix and national-team matching

Owner approved. The build carries 0a45e84 (registry no longer rejected over retired StreamEx/StreamVix coverage) and c244a5e (national-team spelling aliases). Pre-build snapshot `backups/release-source/3.0.0-278` (commit 8bc12ad, source a2ca159a…3b25d); the compare passed before the upload. The archive's signatures verify. Uploaded through the Xcode account: the App Store Connect API key is refused for distribution signing, and the upload script now defaults to the account (113bf42). The API key set the note "Bug fixes", but it cannot answer export compliance (403). The owner answered "no non-exempt encryption" in App Store Connect, as for every earlier build, and 278 was then added to Fotty Internal Smoke, notifying its testers. `ITSAppUsesNonExemptEncryption = NO` is now in Info.plist (82e791e) for future builds. Archive kept in Xcode Organizer.

## 2026-11-11: Broadcast registry rejected since 9 Nov (StreamEx/StreamVix retired in app only)

On 9 Nov the app removed StreamVix and StreamEx, including from `BroadcastRegistrySnapshot.providerCodes`, but the Worker still publishes their coverage rows. A single unknown provider code rejected the whole registry, so every refresh on builds since then (TestFlight 276 included) failed validation, and Watch lost all registry listings: 858 broadcasts and 72 links at 13:50 UTC. Found from Jet 277's private diagnostics (`broadcast_registry_refresh` failures every few minutes). Fix 0a45e84: rows for providers the app does not support are dropped before validation, and the remaining rows keep every existing check. Jet 278: 90 s hold passed and no registry failure was logged (only failures are logged; 277 logged one 3 s after launch). Testers on 276 stay affected until a new upload, or until the Worker stops publishing the two retired codes (needs an owner-approved deploy; the other session's uncommitted Worker edits stay undeployed).

## 2026-11-11: Match national teams across source spellings (source only)

Highfly and the other reviewed sources matched a fixture only when both names normalized identically, so differently spelled national sides (Türkiye/Turkey, Czechia, Côte d'Ivoire, IR Iran, Korea Republic) never found their streams. The whole-name alias list that only catalog admission used is now a shared `NationalTeamAliases` (in `CatalogPlaybackIdentity.swift`), extended with common FIFA/ISO variants, and `ReviewedSportsFixtureMatcher.teamKey` applies it after the club catalog. Whole names only. Squad qualifiers stay part of identity, and "Ireland" means the Republic only in football. Focused Catalyst tests pass (matcher, catalog identity, Highfly, CNC). Not installed on a device and not seen against Highfly's live catalog; the Highfly link is device-only on Jet. Commit c244a5e.

## 2026-11-11: Internal TestFlight 3.0.0 (276), first upload since 206

Owner approved. Release 3.0.0 (276) archived from a pre-build source snapshot (`backups/release-source/3.0.0-276`, commit cd626b8, source SHA-256 93a00678…3e6792); the compare passed before each upload attempt. The app and widget signatures verify, and dSYMs uploaded. The build replaces 275 (archived but never uploaded) because it adds the PR 129 backup fix: a saved channel or non-match event (empty away team) no longer makes private backup fail. Internal-only export (`ExportOptions-TestFlightInternal.plist`). The first attempts failed until the owner signed in to Xcode Accounts again. Release note to set in App Store Connect: "Bug fixes". PR 129 was squash-merged to `main` as b55b059 before the build. Its `ios` and `observation-policy` checks had not finished at merge time; `observation-policy` was already failing (watchdog request count).

## 2026-11-10: Matchday, Search and the Live now card follow Home's one-action rows (source only)

Follow-up to Home slice 3 in the owner-approved watch-first contract. `LiveEventCard` and `HomeLiveSpotlight` keep one trailing action (Watch, bell or none). Details, Match centre and Save/Remove move to a tap on the row (which never starts playback), the long-press menu and VoiceOver actions, and saved rows show the "Saved" cue. The ⋯ `CatalogMatchActionsMenu` and the `MatchStartControls.rowActions` slot are removed. Watch admission and playback are unchanged. Catalyst `FottyTests`: 2,551 run, 12 skipped, 5 failures, all Home visual baselines that already failed on the base commit (stale since the Home slices); they need a reviewed re-record. Not installed or checked on device.
## 2026-11-10: Private Watch outcome record (Month 1, watch-first roadmap)

Each single-player Watch tap (`watchSingle` / optional-source lookup, so Home, Matchday, Search, TV and On air now) now writes exactly one `watch_outcome` record to the existing `FottyQualityStore`: competition and sport buckets, the opaque source family that played or last failed, tap-to-first-decoded-picture milliseconds (playing only), automatic failover count and target family, and the terminal outcome (playing, no_stream_found, failed, cancelled) with its failure category. `WatchOutcomeRecorder` keys pending taps by the scene Watch ID already bound to the player's `playbackCorrelation`; the coordinator owns outcomes until a player mounts, then the player reports picture, failure or cancel. The record has no watch/attempt/source IDs, fixture names, URLs, headers or account data, and new detail keys are validated by the store allowlist. The newest 100 outcomes keep a reserved share of the 250-record buffer so large playback cohorts cannot evict them. Owner Status (Settings, hidden diagnostics) shows a read-only per-competition summary: taps, share reaching a picture, median time to picture. No network, analytics or admission/ranking/playback change.
## 2026-11-10: Fotty is watch-first; adopt the 90-day roadmap

Owner approved a watch-first direction and a 90-day plan (`docs/roadmap-watch-first-90-days.md`): Month 1 makes Watch reliable and measured (private Watch outcome record, cloud playback probe), reaches phone parity, clears the release gates and resumes a weekly internal TestFlight; Month 2 cuts review-only/dormant sources and features, polishes bring-your-own-source setup (Highfly first), fixes national-team name matching and moves the Catalyst suite to CI; Month 3 adds kickoff-to-Watch alerts, a score Live Activity and the match page as the single hub. Each TestFlight upload still needs the owner's explicit go-ahead.

## 2026-11-10: Carry national-team football for the November break (Worker deployed)

Owner approved adding international football and enabling its source. UEFA Nations League, international friendlies and the Concacaf Nations League now come from the existing ESPN adapter under the same exact team/date/status admission, behind a new narrow switch (`FOTTY_SPORTS_INTERNATIONAL_FOOTBALL_ENABLED`); the general public-feed switch stays off, so NBA, NFL, college, MLS, tennis and golf remain off. Deployed as `2026-11-10.international-football-1` from a clean copy of the last commit plus only this change; the other session's uncommitted Worker edits were not deployed. Live schedule covered 52 + 41 + 27 fixtures; 522 Worker tests passed. No app change is required. Highfly may spell some nations differently (Turkey/Türkiye), so its matches may be missing for those until name matching covers them.

## 2026-11-10: Approve the watch-first Home direction (concept only)

Owner approved the Home concept: lead with what can be watched now (Live now card only for a watchable or confirmed-live match; On air now channels always available; Today so far for stumps/finished), one action per row (Watch, bell or none), clock times beyond the last hour, two independent iPad columns, and Settings moved to a gear. Contract: `docs/design/home-watch-first-contract.md`; concept canvas linked there (sample data). Approval is for direction only: no app code changed, and each of the five build slices needs its own tests and Jet visual check. Watch admission, source rules, PiP, reminders, artwork, FPL and Watch two are unchanged.

## 2026-11-10: Clear cricket stumps and break presentation on Jet265

Stumps now says “Stumps · Play finished for today”; lunch, tea, innings breaks, paused, interrupted and delayed play have explicit labels. Home uses neutral moon/pause symbols and does not head a mixed paused-cricket group “Live now”. Shared copy reaches details and scorecards. Single-player match status uses admitted cricket phase instead of a generic Live broadcast fallback; the managed-audio/multi path stays unchanged. Existing lifecycle, source matching, Watch eligibility, freshness and transport guards are preserved.

94 focused Catalyst tests passed with no failure or skip (26.1 test-only deployment override, unsigned local test host); signed normal Release265 installed/launched on free Jet. Current Pakistan–Sri Lanka stumps label, cricket tile, details badge and scorecard were visually readable without LIVE styling. Jet left on normal Home; no source preference changes. No phone/FPL/multi/TestFlight/cloud work. Owned build/test output cleaned after verification.

Highfly stays configured/enabled from264. Its native live programme/90-second hold/basic-control gate remains pending: ICC still reports Day2 stumps, and the latest provider response was Streams Unavailable. Do not substitute setup success, replay or yesterday's daily pin for resumed-play evidence. No automatic future test was scheduled. Receipt: `docs/testing/fotty-source-research-2026-11-10/jet265-cricket-status.json`.

## 2026-11-10: Adding a supported account source enables it; configure Highfly on Jet264

Owner authorized automatic enablement and using the supplied Highfly Premium link on Jet. Add now validates the configured manifest and one bounded catalog page, saves device-only Keychain data, then enables the exact supported provider and refreshes the parent switch. Cancellation, invalid access and storage failures preserve prior setup; unimplemented sources remain explicitly review-only. Removing one configured source disables only that source. No credential is bundled, logged, synchronized or stored in receipts.

53 focused Catalyst tests passed without failure/skip; one consolidated signed Release264 installed. On Jet, Highfly was temporarily switched off, then the owner's configured link was added through masked entry. Validation/save succeeded, the parent switch became on, and reopening setup retained Added · enabled. All other settings preserved. Device Hub paste did not forward a valid link; keyboard entry succeeded. An invalid draft did not change saved state.

Correct a Highfly Test-day join: verified day2 listing 10Nov05:00 UTC can correspond to the Test that originally began 9Nov04:30 UTC. Require exact teams/squad, format, ordinal, current calendar day and same-ID metadata; do not compare subsequent-day coverage hour to the original Test kickoff. Other format/time guards unchanged. Regression covered.

Fresh premium stream response now supplies only Streams Unavailable, not HLS; official Pakistan–Sri Lanka is at Day2 stumps. Home/details remained broadcast unconfirmed without Watch. Setup/enablement passed; actual Highfly native picture/audio/90-second and normal Watch selection remain pending a fresh eligible delivery, not passed. No phone/FPL/multi-stream/cloud/TestFlight changes. Receipt: `docs/testing/fotty-source-research-2026-11-10/jet264-source-setup.json`.

## 2026-11-10: Install source candidate 263 on Jet; next priority is UI polish

Owner requested iPad installation and chose Home, Sports TV and player polish for the next planning discussion. One signed Release 3.0.0 (263), with matching widget version, installed successfully on free Jet after the 195-test source gate. Device inventory confirmed 263 and Home was visually observed after launch. No credential entry, opt-in changes, playback qualification, phone, FPL, multi-stream, cloud or TestFlight work. Highfly needs owner setup in Playback sources before Watch can use it. Discuss/preview the proposed UI hierarchy before implementing; preserve current playback behaviour. Receipt: `docs/testing/fotty-source-research-2026-11-10/jet263-install.json`.

## 2026-11-10: Admit account-scoped Highfly through existing Watch, with qualification kept separate

- Owner supplied configured Highfly free and premium access. Both manifests and the dated sport catalog/meta/stream contract responded. Stage a default-off Highfly adapter (HF1–HF6), secure setup, ordinary source dispatch, guarded HLS relay and descriptor renewal. No account configuration is bundled, logged, placed in cloud registry or written to these receipts.
- Exact UTC participants/squad, same-ID metadata and official cricket format/ordinal/current Test day own matching. Generic channels and notification tips do not identify fixtures. Bounded searches use advertised pagination. Current fixture, enablement and configuration are rechecked; Watch bypasses discovery-session cache for this account-scoped adapter. One rejected destination cannot remove admitted siblings.
- Free cricket and Sky PL channel samples returned HLS and three decoded frames in bounded in-memory preflight. Premium returned the same two named cricket options with a different signed query contract; HLS responds, but premium decode/native playback is unproven. Shared delivery hosting with AS is not publisher independence. No live programme, 90-second native hold, audio, PL/UCL coverage or outage qualification is claimed.
- Pengu's original configured manifest had Live TV disabled. The published Live Sports option exposed sports catalogs in a read-only inspection. Sample cricket declares ClearKey and is not admitted; football descriptor timed out. StreamNexus still needs owner setup. Neither is a Watch adapter yet.
- 195 focused Catalyst tests passed, zero failures/skips; compilation and diff checks passed. Initial test fixture inventories and deterministic session timestamps were corrected before the passing run. No device, phone, FPL, multi-stream, opt-in, publication, cloud or TestFlight changes. Receipt: `docs/testing/fotty-source-research-2026-11-10/highfly-configured.json`.

## 2026-11-10: Prepare owner-configured source access without claiming playback integration

Owner approved PenguPlay, Highfly and StreamNexus setup. Add a separate Playback sources setup section with reviewed public configuration links, masked entry and non-synchronizable device-only Keychain storage. Save validates only the address and preserves previous data on failure; Remove is scoped to one provider. No arbitrary manifest registration, network activation, Watch candidate or account sharing occurs. All three remain pending the owner's configured catalog/meta/stream responses and source-local matching/media qualification. Never label a saved link connected or working. 78 focused Catalyst checks pass with zero failures/skips. Native UI/Keychain interaction and authenticated playback remain untested. No accounts, purchases, device installs or TestFlight. Receipt: `docs/testing/fotty-source-research-2026-11-10/account-setup.json`.

## 2026-11-10: Add only demonstrated new source supply through existing adapters

- Fubo Sports TV27 is staged in the reviewed-TV adapter from the public IPTV-Scraper-Zilla LG catalog. Its shared dummy station ID is insufficient: require the exact published label, reviewed playlist provenance, HTTPS origin and path. Existing opt-in, guarded relay and station renewal remain the owners; no new playback pipeline or generic-channel match inference.
- Fresh master/variant HLS and three decoded frames from a bounded in-memory segment prefix establish compatibility only. Native playback/audio, programme correctness and PL/UCL/cricket backup qualification remain pending.
- TVPass DNS, Moveonjoy expired certificate and Pixelsports/Yupptv 403 results do not justify adding broken choices or weakening transport checks. Empty feeds remain pending. CBS Sports HQ's session/ad contract needs review; EXT-X-KEY alone is not proof of DRM.
- PlavioLive 2.1.6 catalogs responded on a fresh check; HTTP 402 alone does not prove an account/paywall requirement. No AS defect was demonstrated in this task.
- Preserve build 262's official-fixture and direct-discovery architecture and all earlier uncommitted Worker edits. No device, phone, FPL, multi-stream, source-setting, publication, cloud or TestFlight changes.
- Verification: 60 focused Mac Catalyst tests pass, zero failures/skips; native source membership and diff checks pass. Owned build output removed. Evidence: `docs/testing/fotty-source-research-2026-11-10/qualification.json`.

## 2026-11-08: Cloud registry is a live-window hint; retire legacy web stream routes; one owner per monitor

- **Decision**: The cloud broadcast registry is a freshness hint, so its collector spends each provider's existing daily read ledger inside live windows instead of in uniform slices. Caps are unchanged (CS/AS 288, others 96, reviewed TV 576).
- **Why**: Leeds–Tottenham (7 Nov, fotty244 handoff) showed a 75-minute CS gap across kickoff and half-time. `cadence()` forced an eight-read cycle to at least 40 minutes even while live, and kickoff checkpoints postponed the next cycle to repay their advance.
- **Implementation**:
  - `broadcast-registry.mjs`: a live window runs from 30 minutes before kickoff to the listed end, or an estimated duration (football 135 min, T20 4 h, ODI 9 h, Test 8 h), extended while official status is LIVE. Inside a window the cadence is the remaining-day live time × cycle cost ÷ (reads left − a quiet reserve), with a 5-minute floor. Outside windows it is 60 minutes in the 3 hours before a window and 4 hours otherwise. Kickoff checkpoints no longer create repayment debt. Legacy persisted debt is still honoured once, and the durable ledger still hard-stops reads.
  - Removed `/api/live/streams` and `/api/embed/player` (now 404, no upstream fetch). Removed the health fields `catalogProviderCount`/`catalogCoverageMode` and the matching monitor probes. `audit-ucl-readiness --resolve` now counts `listed` links in `/api/live/broadcasts` for `sports-fixture:champions-league:<id>`.
  - Workflows: dropped the `cpl-fixtures` job from `provider-monitor.yml` (it duplicated `cpl-fixtures.yml --update`) and moved the daily UCL look-ahead into `ucl-match-window.yml`. The watchdog observer still watches `provider-monitor.yml`. CPL and UCL failures no longer feed that observer receipt.
  - Worker source `2026-11-08.live-window-registry-1`. **Not deployed.**
- **Verification**: 647/647 web+Worker unit tests, including a Leeds regression (live CS gap ≤ 10 min) and a full four-kickoff PL day simulation (≤ 288 reads, every live gap ≤ 25 min, quiet morning ≤ 5 cycles). Wrangler dry-run bundle passes. No deployment, device or TestFlight action. Native Watch still uses direct fallback only when the registry is empty; making native treat the registry purely as a hint is not done here.

## 2026-11-04: Isolate CNC WBBL discovery and distinguish channel evidence from live acceptance

Private Jet242 stages a new PlayZTV WBBL LS route through normal Watch with exact official and source identity, existing opt-in, original transport fences and guarded renewal. Separate catalog failures and optional-fixture eligibility protect NHL and unrelated cricket. 112 focused Catalyst checks passed; signed app/widget installed and Settings/Home verified. Correct live programme, 90-second hold, controls and any independent recovery are pending the named windows; neither a replay nor a duplicate CDN path establishes readiness. TENIES two additional channel pictures, two duplicate paths, two 503s, StremVerse overlaps and Nebula incompatible routes were distinguished. No phone, FPL, multi-stream, Git/cloud or TestFlight change. See [242 source qualification](../testing/fotty242-new-sources/README.md).

## 2026-11-04: Exact AS joins use existing official fixture freshness

Live post-deployment evidence showed WBBL wrongly rejected after its official receipt aged ten minutes. PR127/cd5edb9 removes that extra limit for exact dated CNC joins only, using existing normalized scheduled/live freshness and original-receipt expiry. Synthetic-clock/current-listing and Test rules unchanged.179 focused tests, both bundles and protected CI pass. No app rebuild; Jet241 unchanged. Actual AS collector recovered117 current records at02:10UTC; decoded football/cricket tests remain pending. Receipt: testing/fotty241-plaviolive/README.md.

## 2026-11-04: Deploy PlavioLive repair; retain physical qualification boundaries

PR126/57b4dc7 deployed from protected main with unchanged configurations and explicit original watchdog activation. Jet241 installed/visually confirmed. New CNC cricket association requires one fresh exact official ODI/T20 owner and same UTC start; no invented source format or Test-day inference. Native AS accepts only the already-reviewed exact HTTPS FanCode path/public-header contract through the guarded relay. 103 native passes/one physical skip, 148 focused checks, clean bundles/CI; runtime fixture migration caught and fixed by CI. Later cloud collector retained155 notices and flags; alerts stay dashboard-only. Upcoming/unmatched fixtures and access-gated PenguPlay/Highfly/StreamNexus remain pending, not playback passes. Receipt: testing/fotty241-plaviolive/README.md.

## 2026-11-04 — Retain current football fixtures when Home loses live-status evidence

## 2026-11-04: PlavioLive migration candidate, not completed playback qualification
- New metadata origin/id replaces the retired empty PlavioHD sports catalog, preserving AS identity/settings and current media restrictions.
- New explicitly dated CNC cricket metadata is parsed; native limited-overs matching requires verified official context and same-ID metadata. Test-day/format facts are not guessed. Its media/header contract and registry format evidence remain unresolved.
- Release240 installed on Jet only. 102 native pass/1 physical skip, 108 adapter/watchdog and39 registry pass; Home/TV launch verified. No live AS delivery newly qualified and no backend deployment.
- PenguPlay public manifest has no catalogs; Highfly setup requires Turnstile; StreamNexus requires token/trial. No signup, challenge bypass, payment or outbound message.
- Owner chose dashboard-only monitoring; keep chat alerts paused.
- Details: docs/testing/fotty240-plaviolive/README.md.


## 2026-11-04: Replace watchdog notification fan-out with quiet incident status

Owner requests one incident system, no GitHub mentions, useful checks retained,
and alerts only for actual viewing impact. PR125 removes per-provider issue
creation, owner assignment/comment delivery and synthetic mention canaries.
The existing bot-owned ledger issue becomes a quiet diagnostic dashboard;
collection, budgets, state and historical delivery receipts remain intact.

The owner bridge retains legacy pending receipts without replay/false ACK and
only queues grouped fresh confirmed app fixture-endpoint HTTP5xx discovery
incidents. Recovery requires all retained causes to resolve. Provider/catalog,
monitor and optional email failures remain diagnostics. No metadata-to-decoded-
playback claim: full playback-impact detection remains uninstrumented here.
PR125 merged as5c074725; normal observer41945708992 passed with zero deliveries.
227 canonical checks and165 current-main candidate checks pass; no device,
Worker deployment, FPL, multi-stream or TestFlight work. Existing chat automation
was found PAUSED and stays paused pending the owner's resume preference.
Publication/live verification recorded in testing/watchdog-incidents-2026-11-04/.


The owner authorized local Home repair immediately, with Jet installation and
physical checks deferred until Fenerbahçe–Liverpool is officially finished.
HomeSportsDiscovery kept unconfirmed fixtures in `items` (and Search), but
`homeSections` selected only live/listed or upcoming items; both Home layouts
therefore omitted Liverpool after its status became unconfirmed. This is a
confirmed presentation defect, not proof of why the upstream status went stale.

The focused repair gives elapsed football fixtures a neutral Awaiting match
update section for four hours after their listed start. This is a presentation
retention bound, not an assertion of LIVE, a renewed status receipt or playback
permission. Existing terminal/conflict vetoes and source eligibility remain.
Fresh live evidence restores normal live placement without duplicates. Both
phone and tablet compositions consume the neutral section after current matches;
interest filters still apply. Added refresh/cold-projection, recovery, terminal
removal and boundary regressions. The existing empty-Home source assertion was
stale against the prior next-club conditional and has been corrected without
changing that behavior. Local test outcome is recorded in the Liverpool239
receipt. Consolidate with the staged audio repair after the game; phone, FPL,
multi-stream and TestFlight remain untouched.

## 2026-11-04 — Liverpool239 audio restored; single-player handoff repair staged

Normal signed239 is installed on Jet. Scheduled registered-descriptor recovery
now uses the fresh fixture identity receipt rather than an unchanged publisher
status timestamp; live/terminal/team/squad/date guards remain. Automatic fallback
reached CS4 and showed the correct Fenerbahçe–Liverpool programme advancing, but
the owner reported silence and local diagnostics confirmed audio_enabled=false.
The scene also showed its audio-transfer failure alert. A clean restart followed
by normal Sports TV → TNT Sports1/TV12 restored the game; the owner explicitly
confirmed commentary. TV12 had a startup retry and a stall before later decoded
progress, so this is not an uninterrupted hold or independent-backup pass.

Local, not-installed audio repair tracks actual mounted Web documents rather
than a selected logical attempt; exact teardown retains its original model and
WebKit surface until suspension acknowledgement. A late actual retirement can
retry the same single audio focus claim without replacing its player/item/attempt
or undoing Pause. Single-view failures offer Retry audio and record bounded local
handoff outcomes; existing two-pane focus policy remains. Focused regression
execution is recorded separately. Do not install over the owner's current game.

After restart, Liverpool disappeared from Home and Search showed Start unconfirmed.
That listing failure remains separate; a Mac metadata request returned403, which
alone does not establish the iPad's cause. No fixture facts were invented, no
security rules relaxed, and no phone/FPL/multi feature/TF/cloud/Git work occurred.
Receipt:testing/fotty235-core-cricket/liverpool239-recovery-and-audio.json.

## 2026-11-04 — Owner-approved Fox release238 and compatible durable state

PR124/c12a800 publishes original Foxtel WBBL matching within the existing
collection budget. Paired Workers deployed as2026-11-04.fox-programmes-1 with
Fox enabled and all existing flags/bindings/activation plus141notices preserved.
Normal post-deploy TV collection16:45:36UTC and watchdog16:46:09UTC completed;
paired safety check passes with141notices retained and all other settings unchanged.
The earlier rollback caveat is superseded: persist legacy-shaped generic Fox
records with a source-root SHA256 proof of the exact original AU record. The
actual prior deployed reader accepts this state; current code restores market
only for a complete matching record, with no read-time rewriting/lease renewal.
222 native tests,672 isolated release tests, eight test-host followup checks,
type/lint/bundles and signed iOS238 compile pass. Jet238 installed/launched;
Home/TV observed. Current Fox replay cannot prove live match Watch or an
independent backup. Phone/FPL/multi-stream/TF untouched.
Receipt:docs/testing/fotty235-core-cricket/fox-release238-evidence.json.

## 2026-11-04 — Fox programme bridge and bounded collection validated locally

Current native code joins reviewed Fox WBBL guide facts to a separately enabled,
fresh exact Australian CS channel. It does not fabricate a TV delivery or a
global entitlement; explicit programme restrictions and media guards remain.
Older clients receive a capability-projected response without new Fox guide/AU
fields. Willow date-selection hints are sanitized, short-lived request hints,
not programme facts, and keep Fox/Willow/ESPN collection within3 reads and the
existing576/day budget. Failure does not renew accepted guide or hint receipts.
222 native,296 backend,251 watchdog tests and both bundles pass. Earlier test
fixture/schema and helper compile failures are preserved in the dated receipt.
New Fox publication/activation needs the separately requested owner approval;
live Watch acceptance remains pending. Rollback must retain the compatible
durable-state reader rather than discard accepted records. Jet237 controls
remain physically verified; no new install/device interaction in this gate.
Receipt: `docs/testing/fotty235-core-cricket/fox-native-integration-evidence.json`.

## 2026-11-04 — Fox collector isolation staged without activation

Default-off shared-source option reads the fixed original Foxtel page under the
existing ledger/transport bounds. Explicit current WBBL programmes normalize to
guide-only references; replay/upcoming facts cannot become current broadcasts.
Healthy Willow/Fox siblings survive failures without renewed retained leases;
durable restart and172focused tests pass, as does the Worker bundle. Two original
HTTP200 guide reads at15:34UTC produced no current qualifying live programme.
No media or device work. Native AU-Fox join, existing new-station use policy,
legacy-consumer compatibility and four-read refresh accounting remain open before
activation; no clearance or Watch success is claimed. See
`testing/fotty235-core-cricket/fox-collector-evidence.json`.

## 2026-11-04 — Original Fox guide coverage review staged

Foxtel FOX CRICKET HD supplies explicit epoch programme times. A bounded pure
parser preserves station/date ancestry, replay/pregame distinctions and reviewed
women's WBBL identities. Nine focused tests pass; fresh original guide and CA
fixtures corroborate two5November programmes, including10-minute early coverage.
Current4November Heat–Sixers is a replay. No fixture LIVE inference, media fetch,
deployment or native programme join. Cloud collection, event-use policy and native
Fox programme integration remain pending; this is not a Watch qualification.
Receipt:testing/fotty235-core-cricket/fox-guide-evidence.json.

## 2026-11-04 — Additional direct CS Willow delivery237

The actualCS3.1.3 main-US-Willow descriptor includes a CDNLive HTTPS HLS route
previously excluded by native admission. Admit only its reviewed HTTPS443 origin,
fixed secure-playlist path and literal token, with exact public Origin/Referer and
advertised browser UA. Keep the guarded relay, public-address/TLS/redirect checks
and all existing channel/fixture identity rules. No arbitrary-origin/HTTP exception.
Old adapter fails the new regression;229CS/relay tests pass0skip. Signed237Jet
normal picker exposesCS2. First attempt503 twice→TV1automatic recovery5.8s/92s hold;
manualRetry CS2decode5.5s/93.664s hold0stalls. Correct Willow NZ–India replay observed.
Keep both failures and success; independence/liveWatch remain unproven. Phone,
FPL,multi,source opt-ins and TestFlight unchanged. OriginalFoxtel absolute-epoch
programme guide now responds; source facts reviewed, no parser/activation yet.
Receipt:testing/fotty235-core-cricket/cs237-evidence.json.

## 2026-11-04 — WBBL runtime validation and single-player controls236

PR122 added the approved isolated CA WBBL cohort and Willow programme matching.
Real production failed because workerd rejects fetch redirect:error before any
request, despite Node success. PR123 changes to manual rejection and tests the
actual deployed workerd flags, including redirect non-following.590backend and
186watchdog checks pass; both paired Workers deployed. Production and Jet admitted
10WBBL rows; normal observer safety passes with141 notices and bindings preserved.

Single-player watchdog counted healthy advancing video as stagnant, preventing
control auto-hide.236 clears healthy progress and rearms after recovery or picker
closure.94 focused tests pass; Jet shows automatic fade, paused Play retention,
resume fade and picker-dismissal fade. Fox CS1 passed90s; Willow236 TV1manifest404
fell back toCS1, then stalled twice including Retry. Preserve that failure beside
235's successful Willow hold; do not call channel/replay testing live-match or
independent-backup qualification.13 protected preferences/42 excluded source hashes
unchanged. No phone/FPL/multi/TestFlight work. Receipt:testing/fotty235-core-cricket/.


## 2026-11-04 — Core viewing scope: PL, Champions League, Willow/Fox cricket

Owner makes Premier League, UEFA Champions League and all cricket carried by
Willow or Fox the reliability priorities; everything else is a bonus. The cricket
target includes domestic and women's competitions, beyond the currently deployed
CPL/West Indies/ICC international fixture scope. Do not silently treat that
existing subset as completion. Keep all eligible TV/CS/AS options and the neutral
reliability/startup ranking; this does not restore the rejected TV-first policy.

Work toward exact programme/fixture association, normal one-tap Watch, sustained
correct-picture playback and genuinely independent recovery. Preserve failed
receipts and distinguish guide coverage, actual delivery and backup independence.
The Willow wrong-programme guide observation (233), upstream CS child403 (234)
and Fox subscription-card result (215) remain open, not erased by this scope
decision. Phones, FPL, multi-stream and TestFlight remain excluded. No device,
runtime, source setting or cloud change accompanies this priority record.
See `docs/testing/fotty-core-viewing-priorities.md`.

## 2026-11-04 — CS current-listing clocks and registry readiness (234)

The actual original same-ID CS response publishes a generated listing clock with a four-hour cache; native resolution used ten minutes while the reviewed registry uses four hours. Align only that generated-listing contract with the existing source lifetime, retaining fresh official LIVE <=600s, exact IDs/pair/envelope, safety and earliest-expiry binding. Independently current cloud and device official receipts must not be rejected merely because refresh timestamps differ. The regression first failed at240/300/599s device receipt age, then passed after validating each expiry independently.

Device tracing also proved cold preflight ran with zero registered matches, then withdrew the one valid association loaded moments later. CS current ODI/T20 resolution now joins the existing bounded registry owner inside its parallel lane. An unassociated generated-clock catalog miss, including while the cached official receipt awaits refresh, releases its discovery ticket without claiming provider absence. It cannot authorize stale playback; scoped negative/conflict/security/HTTP handling remains intact.

230 focused native tests:228 passed/2 optional production-input skips/0 failed. Signed normal Release234 installed on Jet; cold-launch Watch visible and retained after background refresh. Real UAE–Oman Home Watch resolved CS1, but native decoded playback failed at child manifest403; the original advertised child independently returned403 with advertised headers. Preserve the media failure and absence of an eligible backup, not a false playback pass. No phone/FPL/multi/source-setting/cloud/TestFlight changes. Receipts: `docs/testing/fotty234-cs-metadata/`.

## 2026-11-04 — Retain every eligible provider; reliability then startup

Owner superseded the unfinished TV-first direction after observing faster CS streams. Build233 removes TV promotion and extra TV-only wait. Same-match failures override previous holds; equally sustained deliveries compare recent measured startup, with no TV/CS/AS preference or candidate removal. Unknown language no longer gives TV an automatic match-selection advantage. Station language behavior and legacy multi ranking are unchanged. Startup is not measured venue latency.

116 focused physical unit passes, two optional network skips. Signed Release233 installed on Jet. TV1 and CS1 both decoded Willow pictures and remained selectable in the normal source sheet. Short station checks are not exact-match qualification. UAE–Oman normal Watch failed before ranking: accepted registry CS link outlived native current-listing metadata freshness; AS empty, Flix503. Preserve that unresolved receipt and the stale Willow guide observation. No freshness/security relaxation.42 excluded hashes/16 protected preferences unchanged. Phone/FPL/multi/cloud/TestFlight untouched. Details: `docs/testing/fotty233-neutral-selection/README.md`.

## 2026-11-04 — CS token identity, native resume and remaining delivery limitation

Build231 exposed Apple's exact `segment_uri_changed` complaint. Fresh overlapping CS DaddyLive segment URLs differed only by token; a bounded full-byte comparison of both advertised variants matched. Release232 keeps local segment identity stable only for the reviewed HTTPS CDN MPEG-TS token shape, scoped to its originating playlist, and forwards the complete latest advertised URL. Keys, maps, other hosts/query shapes, old Worker-wrapper identity and all admission/security limits remain unchanged. Two new regressions plus the14 existing actual-policy XCTest cases passed.

Jet232 normal inline/native-fullscreen long Pause/Play resumed on CS1 in1.046/0.505seconds without a new attempt. Natural CS stalls recovered to TV1 in5.1–5.3seconds after detection, then sustained90second holds passed. The forced replacement hold failed, as did later sustained CS playback; preserve those failures. Fresh publisher samples supplied20.96seconds of media in49.244seconds, while the app's later failures reported CoreMedia-12888 rather than the repaired URI complaint. This supports, but does not fully prove every upstream cause of, the remaining pacing limitation. No broad workaround or source-guard relaxation is justified. Do not claim all CS reliability finished or publisher independence.

Receipts: `docs/testing/fotty231-resume-recovery/`. Prior130 playback unit passes remain distinct from16 proxy tests and manual physical acceptance. No phone, FPL/multi, publication/deployment or TestFlight change.

## 2026-11-03 — Cricket overlapping Tests, registry and normal Watch

PR121/864ca65 deployed both approved Workers. ICC returned terminal Tests whose explicit multi-day intervals overlapped the request window; kickoff-only filtering rejected the whole collection and stranded current ODI-to-CS links. Admit only verified bounded Test intervals, preserve dates/status, expose finite date/window errors and enforce explicit cricket ordinal conflicts. 176 focused and 186 watchdog checks plus both bundles passed. Production cron restored current NZ–India first ODI and CS coverage; activation/bindings/141 notices retained.

Jet230 normal Watch showed correct CS1 picture within 10s and 91.006s continuity/zero stalls. Deliberate resume then stalled: about27s detection plus5.555s automatic TV1 recovery. TV1 correct programme/91.9s hold and native fullscreen controls observed. CS1 cause remains unisolated; do not call its resume passed or infer publisher independence. No rebuild, phone/FPL/multi/source-settings/TestFlight change. Receipt: testing/fotty-cricket-overlap-2026-11-03/README.md.

## 2026-11-04: Bound single-player resume before automatic recovery

- **Decision:** Inline and native-fullscreen single-player Play share one eight-second progress observer, retaining the current player/item/attempt. A proven expired live seekable window permits one catch-up; a seek jump is not playback. A buffered live wait permits one immediate-play request. General single-player stalls have six-second non-resetting validation; Playing status alone cannot clear a frozen clock. Legacy/multi behavior is preserved.
- **Evidence:** Jet230 CS1 resumed into a stall with about 27 seconds before failure detection and about 33 seconds to TV1 recovery. Optimistic inline Playing and stacked watchdog/validation budgets were confirmed app weaknesses; the provider-side cause was not proven.
- **Verification:** 130 distinct focused physical unit passes, ten new boundary regressions, signed Release231 installed on Jet. One pre-existing Mac-source inspection unit is incompatible with device execution; equivalent source assertions passed locally. Live CS1 test did not begin: XCTest timed out at Apple’s Touch ID prompt. Long pause, fullscreen and forced recovery remain pending. Sixteen protected preferences and42 excluded file hashes unchanged. No phone, cloud publication or TestFlight.
- **Receipt:** `docs/testing/fotty231-resume-recovery/` retains the limitations and must be updated after live acceptance.

## 2026-11-03 — Jet match recovery

## 2026-11-03 — Global Search local input ownership, Jet230

Use local State for active native Search editing; checkpoint the existing
SceneStorage value at dismissal, submission and scene inactivity. Normal229 lost
letters through captured keyboard while Sports TV preserved them. Candidate230
retained full queries; two physical native-key/Clear/reopen tests passed after
Device Hub disconnected its virtual keyboard. The first keyboard-precondition
failures are preserved separately. No internal SwiftUI root-cause claim, provider
repair or new live qualification is inferred. Phone/FPL/multi untouched, no
publication/TestFlight. Receipt: testing/fotty30-broadcast-first/search230-acceptance.json.


## 2026-11-03: Fotty 3.0 broadcast-first private Jet candidate
- Owner chose featured live game, personal club context, live rows and Sports TV.
- Added match-scoped early discovery evidence and wrong-programme automatic exclusion, single-player source presentation, Home hierarchy/reflow and TV search/filter/progress.
- Physical checks found a recursive singleton initialization trap on both devices. Shared sports sync now publishes before framework startup; guarded re-entry and 57 sync/bridge regressions passed. No consent, FPL or cloud-contract change.
- Final normal Release 3.0.0(229) installed on Jet. Actual TV4 NHL 90s and same-owner controls passed; final Release transport check passed separately. No fresh PL/UCL coverage claim.
- Owner stopped phone work; no final repair/install there. Rapid Search complete-string automation remains unresolved despite separate native-key success. No TestFlight/publication/deployment.
- Receipts: [3.0 acceptance](../testing/fotty30-broadcast-first/README.md).

Build 226 keeps single-match discovery open for late alternatives until its existing deadline, rechecks expiring assignments before renewal, and gives a previously playing match one fresh lookup on exhaustion. Repeated AV stall notices share their original timer. Both UCL matches naturally recovered from CS1 to CS3. A further forced loss on Galatasaray recovered to CS4; the equivalent Shakhtar CS4 hold failed. [Qualification](../testing/fotty226-match-recovery/live.json)

## 2026-11-03 — Sports TV station recovery and guide isolation on Jet

Private 225 adds the corroborated UK CS Sky Sports Cricket station alongside TV10. Jet recovered the same WBBL programme after a forced loss in 6.4 seconds, then advanced 91.4 seconds. Recovery replayed roughly one ball. Isolate malformed playlist entries and guide rows while withholding ambiguous ID/slot claims. Upcoming guide-only rows can survive a missing refresh until their original expiry. Worker changes are local. [Receipt](../testing/fotty225-stations/qualification.json)

## 2026-11-03 — FS1 backup and Sky Sports Main Event on Jet

Private 224 admits exact CS station editions for US FS1 and UK Sky Sports Main Event. The FS1 forced-outage test exposed a capitalization mismatch between the provider and the app. Fold letter case for reviewed television names while retaining the full name, region and catalog/meta identity checks. The Mexican variant also claims US country metadata, making full-name equality essential. After correction Jet switched automatically from TV24 to CS1 and showed the same Wisconsin–Iowa game. Sky tuned from Sports TV through Watch. These are station checks. [Qualification](../testing/fotty224-channel-recovery/qualification.json)

## 2026-11-02 — English Sports TV additions on private Jet

Build 223 adds FIFA+, FIFA+ Women, Cricket Gold and Fox Sports 1 (US). Stations use exact reviewed UK, AU or US playlist identities and the existing guarded TV path. Station availability alone does not qualify a match. Four named physical holds passed; FS1 also stalled on its first run. [Receipts](../testing/fotty223-sports-tv/qualification.json).

## 2026-11-02 — Tailored to you Home

Home ranks confirmed live fixtures from the existing filtered catalog. A live followed football club leads, and the next scheduled club fixture appears once directly below. When no confirmed match is live the next club fixture may lead. Compact and wide layouts share this decision.

## 2026-11-02 — Verify fixture assignments and source loss separately

A stale TV diagnostic invalidates its own listing; it cannot discard a valid sibling or grant a station a match. Features use a current fixture-scoped decision, with programme/edition, permitted use and evidence expiry separate from media lease and playback outcome. Generic stations remain station-only. Playback may record observed startup, stalls and media timestamp age; neither decoding nor an HLS clock establishes the correct programme or live-event delay. A user wrong-match report applies only to the displayed delivery, fixture and attempt, including verified same-programme lease rotations. Private source selection compares and logs old/new positions locally without exposing URLs; ordinary builds keep the previous order. Jet alone uses the private trial. A same-publisher fallback cannot qualify as publisher independence. [Verification](../testing/fotty221-broadcast-integrity/README.md).

## 2026-11-01 —220 Watch feedback, positive-history fallback and fresh Retry

Owner approved only these three repairs and Jet tests. Watch reserves visible
pending/Cancel feedback before current-catalog/retained-owner validation; retained
paused playback reopens without stream restart. Initial native startup timeout may
prefer an admitted exact/current alternative with positive decoded history before
repeating the failed route. History ranks; it never proves current programme.

Failed-player Retry owns fresh descriptor-index and CS/AS/Flix/CNC/SV metadata
lookup instead of directly replaying a stored failed choice. Default caching,
paths, opt-ins, budgets and identity/transport guards remain. Failed-pane progress,
Cancel, duplicate suppression and owner/attempt/intent/background/replacement
fences cover late success, failure-only completion and a second alert Retry.

166focused tests/26new methods pass0fail/0skip. Signed app/widget220 installed and
normal-launched Jet. Home Watch showed Finding a broadcast/Cancel promptly;
CS1HTTP404/CS5HTTP502 automatically progressed to CS6decoded23:37:51UTC and was
closed23:38:32. This is not90s qualification or the new startup-timeout branch.
43protected sources+11stable preferences unchanged. Physical Willow/picker/Retry
remains pending: shared Device Hub conflict; targeted Jet XCTest bootstrap timed
out awaiting on-device UI Automation approval before methods ran. Owner action
requested. No phone/FPL/multi, source opt-in, Git/cloud or TestFlight changes.
Evidence:testing/fotty-watch-retry-2026-11-01/.

## 2026-11-01 — Owner Willow/CS follow-up corrects availability assumptions

Read-only Jet219 telemetry corroborates the owner's TV1 Willow decoded22:38:35,
CS1 decoded22:39:13, then selected TV1 HTTP40422:39:19 with automatic CS fallback.
Fresh reviewed publisher metadata still advertises the identical variant; bounded
GET returned200/HLS22:46, with no segment fetch. This is variable current delivery
response, not proof of stale URL, stable decoding, upstream closure or a native
regression. Earlier failed runs remain failed; short owner plays are not90s passes.

Confirmed app costs are pre-acknowledgement main-actor admission/retained-player
checks, silent rejected taps, and retrying a startup-timeout choice before admitted
alternatives. TV already has pending progress/double-tap suppression. Recommend
owned immediate feedback followed by existing validation and a fresh positive
same-event alternative before repeating a failed route; no guard or blanket timer
change. Exact tap latency is unmeasured. No code/build/install/screen control,
phone/FPL/multi/TF/settings/cloud changes. Receipt:
testing/fotty-liverpool-watch-2026-11-01/219-owner-willow-cs-followup.json.

## 2026-11-01 — November evidence audit,218 acceptance and219 follow-through

The owner reported repeated refresh warnings and requested a current November audit/update. Fresh evidence distinguishes the old primary-directory failure flag from a real accepted-registry rejection.218 isolates regressing records/links without renewing them, retains envelope anti-rollback, and imports fresh cloud outcomes into the existing availability index with original timestamps/finite expiry and no duplicate provider HTTP. NoHTTP imports do not consume local request reservations; exact deduplication prevents cached proof renewal.53 registry and85 catalog/index checks pass(no skips; selections overlap). Signed218 is installed on Jet, accepted16:24→19:33, and the warning cleared after source checks. Phone215 remains away/unmodified.

Willow218 decoded then stalled; advancing relay windows and22success/0failed requests do not prove a lease or rewrite problem. Its hold failed and remains failed.219 stages one owned post-decode exact-choice renewal using the existing budget and freshness/identity/security/cancellation fences, without asserting a starvation cause. Juventus–Napoli also exposed a scheduled-status delay: a fresh identity disappeared from Home after kickoff.219 retains Starting within the existing30minute bound, uses identity freshness only for scheduled lookup, and never invents LIVE.263 focused tests pass0skip;219 signed/native gate pending. FPL/multi, source opt-ins and phone remain unchanged.

Bounded official EFL comparison proves404 exact No matches found is its empty-window contract, not route closure.45 source/durable checks and Worker bundle pass; repair is undeployed. Cricket partial/held counts are not whole-service outage counts. Elche later FINISHED receipts and Home removal are consistent with publisher/poll latency, not a proven new mapping regression.

Native toolchain is current; no blind Swift/Worker compatibility-date migration. Web Next16.4.3/sharp0.35.5 and project Node24 selector pass4+46tests/types/lint/standalone build, source-only. Durable official user-local Node24 is verified; global Node25 and owner web outputs remain unchanged. Partial Homebrew library effects are explicitly retained in the maintenance receipt; owned temporary cache cleaned. No Git publication, cloud deployment or TestFlight. Evidence:testing/fotty-liverpool-watch-2026-11-01/.

Final219 gate: signed Release and widget219 verified, no ATS exceptions; installed/normal-launched Jet only. Normal Home Juventus–Napoli Watch automatically recovered its initial TV4 transport error, decoded20:27:32 and recorded90second continuity20:29:02; correct ESPN3 programme observed42:03→43:39 and normal picker remained usable. Home warning cleared without dismissal. The separate TV1 Willow run failed both20second readiness deadlines before any decoded video; the new postdecode branch was not exercised. No timer/buffer/authority change or further build is justified by these receipts.45 protected FPL/multi files and15 stable preferences unchanged; only expected playback-health preference differs. One source-enablement record is unchanged. No phone/TF/cloud work. Current November baseline: docs/audit/Fotty-November-2026-Baseline.md.

## 2026-11-01 —217 late alternatives, TV refresh and expiring Flix backups

216 normal Watch reproduced early exhaustion: AS1/2/3 returned causal403 within one second; CS/FS arrived later and appeared in15options but were never tried. Manual CS1 played the correct match and passed its actual90second interval, then stalled17:30. Subsequent CS2 NFL footage is not programme qualification. CS5 decoded17:48 and correct Liverpool–Arsenal second-half picture advanced58:38→63:45. Preserve every run; never convert one early successful source to a permanent pass.

217 retains early HTTP failures in existing connecting feedback while the same bounded original single lookup owns them, then tries genuinely new matching choices without another tap. Failed URLs are not retried; owner/identity/expiry/security and user-intent revocations remain.70focused lifecycle/late-choice tests pass. No arbitrary unknown-error relaxation or new timer.

Expired TV cache also excluded the entire TV lane before a new registry check: Jet16:24 assignment expired16:30 while backend17:44 had fresh exact TV2.217 adds only a parallel foreground deferred lane, one bounded/shared20s registry read, fresh exact association before playlist/cache use, finite retry/join cancellation and fixed local failure evidence. Aggregate18s/preflight8s source budgets remain; foregroundCS/TV gets32s.50focused checks pass. Initial optional wire test skipped due an environment-prefix mistake; corrected explicit offline production wire test passes1/1, no skip. Snapshot validation is not decoded playback.

Flix registered bindings expire90s; the observed17:30 unknown failures used17:20 choices and were lease refusals, not fresh media failures.217 adds FS to the existing single-only6s exact descriptor renewal path and declares lease_expired for redacted diagnostics. All identity/provider/path/origin/header/query/expiry/cancellation fences stay;8focused tests pass. Source files and Multi behavior outside this single caller remain unchanged. Signed217/native gate pending at this entry; phone215 remains unavailable, exact owner error unconfirmed. No Git/cloud/TestFlight. Receipts:testing/fotty-liverpool-watch-2026-11-01/.

## 2026-11-01 — Fox qualification, phone215 install and urgent Liverpool Watch

Owner approved the narrow Fox HTTP chain and later a private phone install before leaving.215 installed on Jet and Jelani’s iPhone; phone was not agent-launched and subsequently became unavailable. Scoped transport276tests passed, but real native SD and independent HD decode showed a subscription-payment card, not Fox Cricket. No account/payment/access workaround.216 removes unqualified TV20, HTTP origin profile/ATS/helper/tests; complete prototype retained unapplied. CS Fox404 and final Flix Fox369504 remain. SpecialLinks8080 is metadata-only unsupported, not a demonstrated payment gate. This supersedes the pending-approval proposal below. Actual result:testing/fotty-cricket-matching-2026-11-01/fox-215-native-observation.json.

216 adds retained TV reopen, visible cancelable lookup, bounded retry/source management and channel-specific copy/fresh Now/Next Details;59focused tests pass.45protected FPL/multi source files unchanged. Signed216 build and Jet checks pending; no publication/cloud/TestFlight.

UI work paused for owner’s Liverpool–Arsenal phone215 no-stream report. Official LIVE senior PL16:30UTC fixture and current CS/FS/TV links verified. Normal Jet215 Watch selectedAS1, first decode1346ms, correct live programme19:34→24:05,9picker options; cold relaunch also plays. This is not phone/mobile proof. Phone opt-ins, network and exact error remain unknown; no confirmed phone cause or recovery claim.

CS exact descriptor independently took15.93s while native records show parent18s cutoff; client transport allows24s.216 gives32s only to foreground single discovery containingCS, retaining progressiveAS, aggregate18s/preflight8s and cancellation. All30coordinator tests pass, including lateCS/progressive sibling and cancellation/deadline cleanup. Native216 check pending. Receipts:testing/fotty-liverpool-watch-2026-11-01/.

## 2026-11-01 — Resume Fox repair using actual original deliveries

Owner rejected leaving Fox unresolved. The first two original time2shine entries are public HTTP HLS deliveries, not a demonstrated username/password account contract. Fresh bounded HTTP200 manifests and advancing media sequences establish working transport; one bounded advertised segment contains H.2641080p. No Australian programme, native decode, audio or90second playback pass is inferred from that sample. The third xown wrapper returns404; the separate Flix369 TV descriptor exists but its media returns502, so it is not a qualified replacement.

A focused eight-file TV20 SD repair is saved as an unapplied patch: exact original HTTPS metadata/ID/label, finite selected-root runtime HTTP authority and two exact public segment IPv4s, fresh renewal and canonical Fox Watch. Other sources remain on their existing policy; no programme assignment is fabricated, no HD profile is enabled, no account/auth or scheme upgrade is invented. Current Apple ATS documentation supports explicit IP entries on iOS/iPadOS17 and later; the old numerical-IP exclusion is not applicable to Jet27.2.

The new Fox-only HTTP exception is a material security decision currently pending owner response under AGENTS.md. Canonical app/ATS files, Jet214, settings, phone/FPL/multi/TestFlight remain unchanged. Patch application check, Swift syntax/plist parse and independent static review pass; nine regression tests are authored but unexecuted. After approval, apply the focused patch, run affected real tests, build once, and qualify correct Fox picture/audio/90second hold through the normal adapter/guarded relay on available Jet. Do not describe the proposal as installed or Fox fixed. Receipts and unapplied patch:testing/fotty-cricket-matching-2026-11-01/.

## 2026-11-01 — Source-qualified cricket matching and cricket TV placement

Owner approved CS/Willow matching repair, protected publication/deployment and Jet-only acceptance, then requested Fox repair and clearer TV placement. Phone/FPL/multi/TestFlight remain excluded. The dynamic CS FanCode clock is a current-listing observation, not kickoff. Its exact reviewed contract now joins only one fresh official LIVE ODI/T20 with exact participants, fresh same-ID metadata and sibling ambiguity checks. Production loader/DO tests preserve negative/terminal sibling identities before admission. Runtime clock annotations do not expand the stored schema; strict rehydration and the old-client projection retain rollback compatibility. Explicit agreeing ICC limited-overs ordinals and literal Willow ODI/T20 programmes extend matching without guessed formats, timezone shifts, generic-channel assignments or weakened date/squad/transport checks.

PR116/8298f54 merged normally after all protected checks and deployed source2026-11-01.cricket-matching-1 with the existing watchdog rebuild.439backend/186watchdog tests and both bundles pass. All21+3bindings/vars, original activation and131notices compare unchanged; normal post-rollout collector completion observed. Native189matching/30validation/169TV-CS gates pass (overlap, do not sum). Signed214 app/widget installed; landscape/portrait TV grouping observed. A regression caught the new canonical Fox inventory entry being incorrectly required to have a generic TV binding; the correction retains separate canonical cricket ownership.

First Willow TV1 Watch decoded, then its manifest request timed out; automatic CS fallback also stalled. Fresh original TV1 leaf metadata subsequently advanced. A later fresh TV1 Watch sustained advancing branded native picture and a recorded90second continuity sample. Both runs remain separately recorded; no unproven local renewal defect or permanent reliability claim. Normal Fox CS1 Watch/Retry returned404. Exact LiveTVCollector Bangladesh Fox entries were traced to their original playlists, which use public HTTP-only HLS/token routes (the opaque path does not establish account credentials); no compatible HTTPS replacement established. The separate generic US Fox Sports DRM entry is not Fox Cricket. A failed CS route is not a global channel outage or proof the friend's other delivery fails.

Spanish mini-guides come from reviewed ESPN Uruguay coverage. Broad English guide supply is absent, not hidden by a language filter; accepted Willow current programmes can render without borrowing another market's guide. Live repaired fixture Watch remains pending an eligible exact current match. The original ICC13:36UTC receipt has no LIVE row; Afghan–Zimbabwe3rdT20I is scheduled14:30UTC, reviewed Willow programme15:30UTC. Never reuse ended Namibia–Ireland or convert future schedule/preview footage to a live pass.43protected files/eight protected preferences match. Subsequent owner navigation was not an app regression; preserve their recents.

Receipts:testing/fotty-cricket-matching-2026-11-01/. No public media URLs, credentials, private IDs or raw preferences retained in those receipts.

## 2026-11-01 — Discovery directory qualification and English TV17

Owner approved using LiveTVCollector to discover additional English sports TV, then tracing leads to original source metadata and testing through normal Fotty Watch on Jet. Collection output is unsuitable as playback authority: inspected collectors disable their optional HTTP checks, discard channel/header details, and status-only validation does not prove native playback. No collector scripts are installed or executed.

Four current HTTPS candidates were staged together in private211 and passed333 focused tests. Actual Jet Watch qualified beIN SPORTS XTRA with branded native video advancing beyond90seconds. CBS Golazo and separate Willow Sports masters/leaves respond, but their media returns403 through the guarded relay before picture. Fubo's original generated-US metadata exposed a valid audio/x-mpegurl MIME discrepancy; a source-scoped correction passed45tests, then a bounded advertised-segment check returned403. All three unqualified deliveries and the now-unneeded Fubo/MIME expansion are removed from final212; final affected44tests pass. Keep stable TV17 instead of recycling failed candidate IDs. Existing TV1–15, source choices, parser/network/expiry guards and station/fixture boundaries remain.

This adds a station, not verified live PL/UCL match assignments. No arbitrary playlist import, geo/access workaround, generic-channel-to-match inference or dependency on LiveTVCollector's daily export. Owner's phone/FPL/multi/TestFlight/cloud/Git publication remain excluded. Receipts:testing/fotty-tv-discovery-2026-11-01/.

## 2026-11-01 — Sky Football delivery and single-TV recovery

Owner requested Sky Sports Football repair and fewer channel retries, with Jet-only acceptance; phone/FPL/multi/TestFlight excluded. Original TV11 currently exposes HEVC in MPEG-TS: Apple HLS shows audio but no video, both direct and through the actual relay. An older local H.264 segment is not proof of that later live contract. Fresh CS NETWORKS exact UK catalog/meta/stream linkage supplies a compatible alternate through existing guards, attribution and opt-in. Ordinary Sky Watch includes it; no invented programme assignment or security exception.

Physical210 exposed a second defect: shared-CDN TNT success made Sky appear proven before its alternate arrived. Single-TV startup evidence now uses station/host keys while preserving legacy aggregate ranking for other contexts. On a cold tie the verified Sky alternate precedes TV11; actual positive continuity/startup evidence still wins. Reviewed-TV gets the existing once-only verified-frozen-window renewal; late fatal callbacks cannot resurrect terminal single attempts. Explicit Retry remains supported.

331focused tests and signed Release pass. Final Jet210 ordinary Watch selects CS1, advances96.9s, exposes native Pause/Play and reopens correctly; earlier manual-CS hold124.9s and failed TV11 Watch remain separate. TNT2 ordinary first-start hold116.3s passed with the same recovery implementation before the last ranking correction. No natural frozen recovery, audible commentary, live PL/UCL programme or new PiP pass claimed.43protected files and device opt-ins/preferences unchanged. Receipt:testing/fotty-tv-recovery-2026-10-31/.

## 2026-10-31 — Dedicated TV tab and English-first channel experience

Owner requested Sports TV on the navigation bar and rejected the Spanish-heavy selection.209 adds TV immediately after Home, removes the Home sheet/link and uses an adaptive full-screen channel grid. The existing single-player owner is reused. Unset commentary preference defaults to English; explicit choices and Spanish backups remain. Local favourites/recents and positive90-second continuity inform single-stream ranking; continuity is not programme qualification. Phone/FPL/multi remain unchanged; no new TestFlight.

Six finite English station contracts add Sky Sports Cricket/Football, TNT Sports1/2/3 and USA Network. Exact published IDs, paths, headers and opaque renewal query are bounded to two reviewed public playlists; existing TLS/public-IP/redirect/expiry guards remain. Five stations share one CDN; different labels or hosts are not independent-supply proof. New English stations cannot borrow Uruguay or main-Willow guide assignments. HTTP-only alternatives remain inadmissible. NBC208 passed normal native video; separate Willow Sports403 candidate is excluded, main Willow unchanged.

209 passes90 focused native tests. Actual normal Watch observations include sustained TNT1/2/3 and USA video after retained initial failures. Sky Football failed to decode; Sky Cricket first stalled after positive90-second continuity; its fresh retry then sustained video beyond that earlier stall window. No unproven relay root cause or live PL/UCL pass is claimed. Channel/nav changes do not justify repeating PiP/fullscreen suites; QA-Playbook records this owner preference. Receipts:testing/fotty-tv-next-2026-10-31/.

Earlier PR115/99658b6 guide/typed MLB/NHL joins deployed with matching watchdog after534backend/186watchdog checks, preserving old clients, accepted registry, expiry, all21+3bindings/activation/schedules/130notices. Normal collector01:46UTC observed. Full207native baseline2,438passes/9physical skips; affected158passes. This channel/nav batch makes no further cloud publication.

## 2026-10-31: Build206 released to the existing internal TestFlight group

Owner explicitly authorized TestFlight and required the notes to say only “Bug fixes”. Apple developer agreement acceptance was completed by the owner. Final simulator-free qualification passed2,425 runnable tests,9physical/live-only skips and unsigned iOS Release. No shipped Swift implementation changed during release preparation;237app/widget/project inputs match the starting receipt. Obsolete cricket lifecycle/club-identity test oracles were reconciled with already-accepted production contracts. The visual fixture's synthetic shared NSCache badge was evicted under full-suite pressure; CI now runs its unchanged mandatory assertions in a fresh host before the other units. Ten current-renderer captures were individually reviewed; original Xcode27A266a PNGs are retained unchanged, without relaxed pixel limits. Snapshot checksum proofs are restricted to exact reviewed manifests and actual copied Swift bytes;17helper tests pass, including rejection cases.

Final1623-file immutable source commit51de107/source0d7cf644, pre-archive and pre-upload comparisons, signed app/widget versions, strict signatures and dSYM pairing passed. Xcode uploaded the internal-only package20:00:23Tobago; Apple confirms VALID/INTERNAL_ONLY/IN_BETA_TESTING. Only existing Fotty Internal Smoke is assigned,13testers; en-GB notes exactly “Bug fixes”, existing auto-notification true. Current crypto implementation facts and the owner's existing outside-France answer completed compliance; no crypto edit or repeated country question. Availability is not inbox receipt/installation or proof of pending live PL/UCL programme gates. Devices, FPL, multi-stream, source choices, cloud deployment and tester roles were untouched. Receipt:releases/Fotty-2.0.1-206.md; testing/fotty206-release-2026-10-31/. Owned packaging output is removed after preserving these small redacted receipts.

## 2026-10-31: Football TV expansion206 and automatic regional assignments

Owner approved two agents to broaden the Willow-only GitHub TV adapter, then explicitly approved focused publication/deployment and the existing watchdog compatibility rebuild. Native206 retains TV1 and finite TV2–TV8 station identities, exact channel-specific renewal, all matched stations in ordinary source resolution and dual-header V2 negotiation. Raw iptv-org country-playlist HTTPS alternatives are used through existing public-IP/TLS/443/header/redirect checks. No phone, FPL, multi-stream or TestFlight changes.

One consolidated signed Jet build passed82 focused native tests. All seven additional ESPN deliveries decoded90 seconds through the actual adapter/guarded relay, with station watermarks observed. TV3 stalled after56seconds on the first run, then passed90seconds on the retained retry; relay evidence did not prove a root cause. A transport hold and station number are not regional programme/live-fixture or normal-Watch/control acceptance. Those PL/UCL gates remain pending actual current fixtures.

PR114/7d74c40 passed519backend tests and all GitHub checks;186watchdog tests and both bundles pass. The fixed official ESPN weekly RSS admits explicit Uruguay linear-channel assignments, excluding Disney-only rows. Real accepted fixture/source joins covered both PL listings and17UCL listings; the remaining source spelling AEK Athenas was repaired by a literal ESPN-local alias and replayed with its original clock/expiry. Original title/event identity remain; central badge/FPL catalogs are unchanged.

The registry uses already-budgeted DO deadlines to prevent a5minute cron rounding7.5minutes to the10minute expiry. Near-live demand transitions and independently healthy Willow/football siblings retain freshness; caps remain576reads/day/eight reads per cycle and ten-minute facts. One RSS read includes discovery and weekly content; no Mac/AI task maintains it. RSS remains bounded1MiB and programme coverage is partial, not every match.

Playback21d7abe1/watchdog1a3d08f2 now use2026-10-31.tv-football-1. All21+3bindings, original activation/configuration revision and130notification identities were verified retained; local reader-version import aligned without resetting state. Normal22:40:22UTC cloud collection fetched40assignments/29accepted-fixture links including2PL/18UCL; V1/legacy projections exclude football. Receipts:testing/fotty-tv-expansion-2026-10-31/.

## 2026-10-31: Missing Watch root repair published and deployed

Owner reported Villa–Fulham Watch disappearing after CS2 had played. Fresh cloud evidence at21:23/21:28UTC showed terminal-rollback admission failure holding all six football leagues, revoking native lookup eligibility for the unrelated live fixture. Owner approved focused publication/deployment, then explicitly approved the existing watchdog compatibility rebuild. PR113/e5a273f isolates valid/held records and competitions, preserving accepted terminal facts, identity/duplicate/replay/expiry guards.496backend units and186watchdog checks pass; full GitHub gates passed. An old crosscheck test used contradictory same-event identities and was corrected to independent fixtures. No unrelated staged score patch was deployed.

Playback3a0c5136/watchdog6660fa8b now use2026-10-31.fixture-isolation-1. Existing activation flags, original watchdog activation and130notification identities were verified retained. The local owner-alert version import was aligned without changing retained reader state. Jet Home visibly restored Watch for Villa–Fulham and other football at21:42UTC; the currently connecting player was only minimized/restored, not claimed as fresh playback proof. No app rebuild/installation, phone, FPL, multi-stream or TestFlight operation. Owned outputs cleaned. Redacted receipts:testing/fotty-source-connection-2026-10-31/.

## 2026-10-31: Consolidated source matrix completed with one device build

After the owner rejected incremental rebuilds, the completed tool safeguards/local checks were built once as205 and the actual eight enabled modules collected on Jet against fresh accepted Villa–Fulham identity and independent in-progress status. CS2 passed90seconds with878decoded frames/93.54seconds progress; a separate ordinary-picker run visibly confirmed CS2 and the correct programme. Other delivery failures, missing/empty catalogues and unsupported coverage remain explicit, not converted to passes. Four runner and44local fixture isolation tests pass; the existing180CS/SV passes remain. Source redaction's new Swift regression compiled but was not separately executed. No product source changed during this batch, new Watch routing, backend publication, phone/FPL/multi change or TestFlight. Owned build/result/raw output/keep-awake cleaned. The already-staged per-record fixture-isolation repair is locally tested, not deployed. See testing/fotty-source-connection-2026-10-31/Results.md and separate batch-2 receipts.

## 2026-10-31: Isolated source connection tool; gate interrupted

Owner requested an actual-code all-enabled-source PL inspector before Watch reconnection, Jet only; phone/FPL/multi/TestFlight excluded. Build205 contains a compile-only resolver inspection entry, native decoded-frame collector and bounded CLI. Web XCTest hosting aborts were not fixed by configuration/sleep changes; its experimental observer/product hook was removed and a manual ordinary-app gate made explicit. Product web source matches its pre-task hash.

SV original parsing no longer rejects73 unrelated categories or the exact non-fixture Simulcast programme. A fresh verified CS stream response took16.039s versus the client's12s bound; CS-only request23/transport24 retains metadata/shared sibling budgets and all guards.180CS/SV tests pass including the controlled delayed-response regression;3Python tests and membership/syntax checks pass.

Real earlyAS403/FS502–504, later manual correctFS1/FS2 footage, and normal web failure are separate dated receipts. The last205 native run was interrupted at owner process correction; no formal90second qualification, universal source availability, Watch reconnection or job completion is claimed. Owner explicitly rejects incremental patch/build/test loops: consolidate the complete remaining failure/fix batch and local checks before one device candidate. No publication/deployment/distribution. Owned temporary products/private data and keep-awake process cleaned. See testing/fotty-source-connection-2026-10-31/Results.md.

## 2026-10-31: AS203 source-local football compatibility repair

- **Intent**: Owner explicitly asked to solve missing AS instead of repeating diagnosis. Football/PL first; Jet only, no phone/FPL/multi/TestFlight or cloud publication.
- **Repair**: The current Roxie civil-date contract associates only with a unique fresh accepted official senior-men fixture. Official kickoff/competition/status remain authoritative; no site-time offset is guessed and no LIVE status is manufactured. Fresh same-ID meta and latest official status are rechecked; optional catalog channel-count text is cosmetic. Source-local exact HTTPS443 HLS delivery on admin2.formaturamaxi.com.br reviewed, preserving all public-IP/TLS/header/redirect fences and the existing papacito route. Stremio typed notWebReady is not a native-HLS prohibition.
- **Verification so far**:101focused tests,100pass/1explicit physical skip/0fail; signed app/widget203 verified and installed/launched Jet. CurrentPL descriptor2valid; existing203AS1 decoded receipt17:17 unobserved visually/short, not90second acceptance. Physicalgate blockedbyJetpasscode afterMac access recovered.52protected hashes/sourcechoices unchanged;2existingFPLruntimecache values changed, noFPL UI/source operation. Descriptor/HLS/TS-prefix evidence is not native decoded playback. AS default catalog has optional search only, no missing pagination; current Tottenham search empty. Live source/picker/90second/native-control acceptance remains pending and is recorded in testing/fotty203-as-football-2026-10-31/.

## 2026-10-31: Football-first shared Watch repair and AS compatibility diagnosis

- **Owner direction**: One sport at a time: Premier League first, Champions League next. Jet only; keep phone/FPL/multi/TestFlight unchanged. User explicitly permitted a focused read-only agent; it reviewed source contracts and the ordering change.
- **Cloud**: Protected PR110/111 through required checks, mainb91812f. Typed temporary30minute identity retention, reviewed club aliases/canonical IDs and backward-compatible typed ODI/T20 early coverage (separately owner approved) deployed as source2026-10-31.broadcast-matching-1. Exact21/3bindings/originalactivation/129notices retained; actual later collector completion verified.472backend/186watchdogtests pass. Native identity receipt separated from publisher status-change timestamp; no manufactured LIVE/terminal updates.
- **Single Watch**:199normalHome ManCity–Brighton automaticallyCS5; correct livepicture>6minutes, but101.5second startup failed.200directfirst2.53s exposed unknown web family jumping ahead.201 bounded first-choice grace (starts only with candidate) and direct-first recovery; independent review supplied diagnostic-before-choice regression. Actual201 identified positive family/host history draining failed siblings;202 restores attempt-local family turns after failures while keeping all sources and prior speed evidence for first turns.49currentfocusedtests pass; signed202installedJet; normalHomeWatch automaticallyCS2before remainingFSsiblings, correctprogramme>121s. Firstplayerattempt→decoded33.87s stillslow; no calibratedtaplatencyclaim. Earlier212ownership/retry/healthtests pass.201CS2 normalHome correctprogramme/fullscreen/pause/resume observed; PiP overHome113.056s/systemRestore passed; objectidentity uninstrumented. No full readiness claim.
- **AS**: Fresh1.9.130 football catalog15:48UTC contains29Roxie rows, including currentPL targets. Same-ID meta supplies only “site time”, no verified timezone/original linkage; descriptor also uses a different host from the reviewed papacito.cfd contract. Configure/homepage did not establish missing authority. AS is enabled, not absent supply; current adapter is incompatible. Existing rules conflate security/identity with brittle exact-format/host assumptions; user is discussing this, no AS fence was bypassed or guessed offset adopted. Repair needs maintained timing/provenance plus narrowly reviewed delivery compatibility. Earlier1row and later29rows used the same route; do not fabricate the earlier row’s title or a precise migration time.
- **Unresolved**:201firstlaunch temporarily retained unavailablePL cache/noWatch despite healthy public data; exact native validation/acceptance admits current payload. Fresh relaunch restoredWatch. No transport/root-cause proof yet, so no speculative patch. UCLlive and cricketphysical remain open. Evidence in testing/fotty201-football-watch-2026-10-31/.

## 2026-10-30: Build195 native fullscreen handoff and actual live PiP acceptance

- **Fix**: Physical194 testing exposed a requested fullscreen lease detaching inline video while source-sheet dismissal temporarily prevented presentation.195 commits inline detachment only after retained AVKit presentation, with bounded same-window/same-lease retries and exact-owner cancellation/rollback. Five regressions plus existing fullscreen/contracts/ownership/retry total143passing tests with no skips; same player/item/source/intent invariants remain guarded. Signed app/widget195 installed onJet.
- **Actual live test**: Official fresh football-data snapshot corroborated Lille–Lens at30October20:05UTC, senior men/Ligue1/LIVE. Normal Home Watch produced12FS/CSoptions and correct decoded programme. CS1 later returnedmanifest404 after25s frozen playlist; recovery retired its fullscreen and moved toCS2. Diagnostics proved the presentation had succeeded; no speculative second presentation change was made. CS2 advanced over90s, native pause/resume worked, system PiP was visible before Home and advanced over Home for118.773s. System Restore returned without prior app activation; same presentation/attempt receipt retained. Physical object identity was not independently instrumented. Match left playing onJet.
- **Cloud and limits**: association2/watchdog ordinary collector completed20:01:01UTC, original activation/all127notices/bindings preserved. Native194 accepted8families/21scopes/1434observations/27links(1listed); metadata is not decoded proof. FS1's502 and CS1's404 are retained failures, not all12successful sources. PL/UCL/fresh cricket/other deliveries/controlled ABR remain explicit gates. Temporary Home absence recovered automatically; no confirmed erasure defect and no speculative consumer edits.
- **Preservation**:50protected FPL/multi source files,6private FPL values and source flags unchanged. Phone189/shared121 untouched. Receipts:testing/fotty194-shared-watch/. LiveNetTV remains static research in audit/livenettv-2026-10-30/, no new provider enabled or protected algorithm claim.

## 2026-10-30: Shared fixture Watch association repairs and bounded LiveNetTV APK review

- **Product**: Preserve match → Watch → existing source options across the app. Channels remain independently usable; a generic channel name never proves its current programme. Remove the unconditional channel programme diagnostic; do not manufacture match availability or add a Check streams step.
- **Cloud**: Protected PR106/a7d030e and107/76685a7 each passed seven checks. Deployed association2 playback f0765380 and matching watchdog47d9ac22. Current US main-Willow programme lane uses the selected IANA zone and explicit dated Test context; old clients retain a seven-family projection, capable clients receive eight. CS NETWORKS identity survives fetched cohorts, while market proof requires its literal US contract. Existing bindings, budgets, flags, original activation and127 immediately preceding notices remain preserved. The new guide has its own bounded allowance; no Mac/AI scheduling dependency.
- **Native**:194 privately joins current programme and CS channel facts, preserving original identities/expiry and rechecking source opt-in, exact official fixture/day and fresh same-ID descriptors. Whole-Test/ICC context, FS bound sessions and reviewed six-league/UCL parity, AS dated-DLHD count/category and CS decorative status fixes retain date/squad/competition fences. No region/time guesses or widened match tolerance. AS Roxie site-time remains unverified.
- **Evidence**:466 backend units and186 watchdog tests pass; final native gate402total/399pass/0fail/3physical skips. Signed194 app/widget verify;50 protected FPL/multi files unchanged. Real193 Home LeHavre–PSG normal Watch displayed six choices and recovered from failed CS1/2 to correct CS3 decoded picture over90seconds. That is one Ligue1 delivery, not PL/UCL/cricket or all-source qualification.194 installation is blocked by Jet lock/developer-image mount;193 remains installed and194 physical checks are pending. Phone189 and shared121 are untouched.
- **REA**: Existing REA6.4/JADX0.7.1 statically inspected the downloaded LiveNetTV5.0.1 APK with one384MiB worker. Only16 protected/bootstrap classes are exposed.232 compiled UI XMLs establish declarations for channel/event browsing, quality/link/retry/reporting, not actual algorithms or performance. Catalogue/cache/recovery logic and server data remain unknown; no APK execution, target API/media requests, credential extraction or new provider qualification. Typed picker failure results and device-local quality intention are recommendations, not implemented features.
- **Receipts**: testing/fotty194-shared-watch/ and audit/livenettv-2026-10-30/. No phone/FPL/multi/TestFlight change; live qualification and final physical acceptance remain explicit.

## 2026-10-30: Registry105 activated; native192 TV1 and bounded frozen-window recovery
- **Authority**: Owner approved registry publication/activation plus TV-source and buffering work; clarified fixed-quality sources are valid and working additions should be enabled. Jet only; no phone/FPL/multi/TestFlight changes.
- **Cloud**: Protected PR105/c4cb85e,7green checks; clean playback87686309 and matching watchdog945283f6 deployed. Additive BroadcastRegistry only; all prior cloud bindings/variables/namespaces,11Oct activation and125notices preserved. Actual later collector completion passes. Cloud cron/alarm owns collection without Mac/Codex. Provider-supported cadence and one groupedT−5 moved slot retain actual-read caps/debt/idempotence.
- **Native**: Separate TV1 main-Willow fixed-provenance/ID/HTTPS native channel lane; fresh-on-tune/renewal90s binding and current opt-in, no fake programme link. TV1 enabled onJet; existing seven choices preserved. Genuine variant ladders retain Auto/Saver; fixed720p stays eligible. Finite relay progression/access-log evidence, one verified-frozen-CS/AS fresh-descriptor retry sharing existing budget, explicit Retry/reselection fresh requirement and pause/cancel/ownership fences. No global buffer inflation or quality exclusions.
- **Verification**:399pass/0fail/1explicitphysicalskip (400total), signed normal192 installedJet. Independent review caught/fixed explicit-retry dead end and TV expired-reselection trap. Normal Willow Watch auto-selectedTV1; advancing picture >90s, native fullscreen/pause/resume, actual HomePiP >60s and system Restore pass visually. Same player/item object identity uninstrumented. Reselection completion is recorded in testing/fotty192-tv-buffering/.
- **Limits**: First cloud drain743observations/7families but0listed associations (3conflicts/9needsVerification). Known StreamEx/Score failures isolated. Fox guide empty; Willow programmeUTC/Test-day/PL/UCL acceptance and controlled weak-network ABR proof stay open. HTTP200 never substitutes for actual programme/playback proof.

## 2026-10-30: Shared registry191 built; activation/live gates open
- **Decision**: Cloud DO/cron maintains seven reviewed families independent of Mac/Codex. Exact registered initial admission requires no old primary alias. Preserve local opt-ins, source identity and delivery guards.
- **Implementation**: Typed observations/links/reasons, durable budgets/backoff, original expiry and independent failure retention, same-ID native resolution, competing-owner veto, per-fixture rotation, scope-correct fallback and fresh canonical renewal. Test/day/programme authority stays strict; no retained media URLs.
- **Verification**: Jet191 signed app/widget/install;746native pass/0fail/4physical skips;63new backend/202clean activation checks pass.54protected hashes,7sourceflags,7private prefs preserved. Willow decoded but failed28/46s holds; Fox advanced>90s. See testing/fotty191-broadcast-registry/ for exact outcomes/open gates.
- **Activation**: OFF pending separate approval. activation.patch reconstructs83b1a44 plus registry, excluding9unrelated runtime edits. No publication/deployment/TestFlight; phone/FPL/multi untouched.
- **Research**: Auto/Saver needs real HLS variants. iptv-org/epg, IPTV-API, IPTVnator and TVheadend offer patterns; Fox guide lead unqualified. No new scraper/feed enabled.

## 2026-10-30: Channel190 and the unfinished holistic catalog
- **Decision**: Restore Willow/Fox through reviewed independent CS NETWORKS identities. Owner correctly rejected this as completion of the shared-catalog task.
- **Implementation**: Canonical undated channels; opt-in exact metadata/guarded descriptors/bindings; appwide bounded preflight, separate readiness/URL expiry and fresh listing Watch with newer-negative veto. Test ordinal/end remains staged.
- **Verification**:405native/60backend tests pass; signed app/widget/Jet190 install verified. Willow displayed SA–Australia/Willow Live12:21UTC. No90s/Fox/fullscreen/PiP pass.44protected files,7sourceflags,6private prefs unchanged. Phone189/shared121 untouched; no publication/deployment.
- **Open**: Seven-source hints are not a broadcast database. Original observations/reasons and programme links are missing; Watch matches again; global cursor can starve fixtures. Proposed shared typed broadcast→event registry and Test occurrence model: testing/fotty190-cricket-channels-2026-10-30/Holistic-Catalog-Findings.md. No generic channel inference/completion claim.

# Fotty Decisions Log

## 2026-10-30: Install existing Watch candidate on Jet; keep fixture status separate from availability

- Correct the device mismatch: Jet187 still exposed Check streams while phone189
  held the approved Watch flow. Install identical signed189 on Jet; preserve
  source choices and6FPL/private profile keys. Actual Home/inline/fullDetails
  Watch and one-tap lookup verified. Same native fingerprint/124focused tests;
  no new native edits, repeated unit gate, phone/multi/TestFlight/backend change.
- Namibia–Ireland Watch returns Broadcast not ready; no video/PiP pass. Finished
  NZ–India cannot be reused; current CS dates fail ordinary matching guards.
- Read-only SA–Australia diagnosis: official Day4/Lunch, CS/AS Day3; daily source
  timestamp differs from Test initial kickoff. A verified source-local Test-day
  occurrence model is missing. Keep original identity and ordinary15min fences;
  never infer daily dates. Aggregate no-exact-match is not proof all providers
  lack streams. Fixture LIVE, actual play and Watch availability are distinct.
- Receipt: testing/fotty189-jet-watch-2026-10-30/README.md. Further matching/status/
  error-copy repair is identified, not implemented/deployed by this diagnosis.

## 2026-10-29: Shared fixture catalog and one-tap single Watch candidate

- Keep accepted official fixtures as identity/status authority; collect metadata
  across the seven reviewed source families, enabled sources only, independent of the main
  broadcast list. Source adapters share bounded scope reads, never eager per-match
  streams or player pages. Missing, unverified, conflicting, unsupported and failed
  cohorts remain distinct; one failed sport must not erase a complete sibling.
- The process-local catalog index holds bounded metadata evidence, not playable
  URLs, decoded-playback proof or independent-supply guarantees. Current receipt,
  exact teams/squad/date/competition/cricket context, terminal facts, source opt-in,
  generation and expiry fences remain mandatory. A fresh partial provider response
  cannot renew listings retained only for browsing; CS 07:30 versus official 07:00
  remains unverified rather than a silently corrected kickoff.
- Owner rejected a separate Check streams step. Within existing timing/admission,
  one Watch action starts the normal resolver, mounts the first valid source and
  appends later choices to that same player without restart. Mounted discovery is
  scene-owned; late callbacks still recheck the current fixture and enabled family.
  Catalog metadata never turns a future/scheduled fixture into LIVE or a session.
- Owner changed the private test target to Jelani's iPhone and approved CS there;
  Jet iPad remains untouched. FPL/multi-stream are unchanged. No TestFlight, Git
  publication or cloud deployment is authorized by this candidate.
- Initial shared-catalog native gate: 431 passed, 4 physical-only skipped; separate
  clock/context gate:52 passed. One-tap/admission/presentation gate:124 passed,
  zero failures/skips. Final signed/device acceptance remains unclaimed.

## 2026-10-29: Prioritize source repair over additional alert setup

- Owner clarified that existing alerts are sufficient for the current task;
  prioritize actual discovery, independent working supplies and playback.
  Additional email/accounts, monitoring and deployment-safety candidates remain
  on hold/unpublished. getfotty.com is unavailable and not an alert dependency.
- Retain verified terminal facts separately from playable rows so stale open
  Details/saved objects and late lookup results cannot start finished/cancelled
  official fixtures. Exact date/team/squad/competition conflict checks and an
  already mounted player's ownership remain unchanged.111 native tests pass.
- Repair only AS's observed DLHD envelope: exact advertised AS meta plus the
  original producer's explicitly dated GMT day/category/event section supplies
  missing source date authority. Use actual closed ancestry and visible fields,
  preserve malformed/duplicate vetoes, strict clock/date agreement, fixed bounded
  public HTTPS metadata route, cancellation/generation fences and5-minute cache.
  No media destination, player, legacy AS, cricket, FPL or multi-stream change.
-15 new DLHD regressions and offline actual-public-page parsing pass. Scoped
  adapter/matcher gate92pass/0fail/1physical-only skip. A finished Cup row proves
  schema matching only. Required live PL/UCL/cricket, independent-source outage
  drill and corrected physical PiP remain open; no install/TestFlight/publication.
  Unsigned generic iOS Release app/extension compile passes from frozen source.
- CS NZ–India30Oct07:30 conflict with ICC/BCCI07:00 is confirmed in its original
  public Ak47 schedule. Do not rewrite the source date or widen15min admission.
  Wrapper ancestry overlaps and AS cricket absence remain explicit limits.
- Receipts: testing/fotty-resilience-2026-10-29/README.md. The existing bounded
  live-acceptance follow-up continues actual source gates, not extra alert setup.

## 2026-10-29: Publish bounded broadcast catalog and preserve truthful Jet187 acceptance

- Owner approves five ordered broadcast-reliability repairs and Jet-only outage/
  playback gates. Phone, FPL, multi-stream and TestFlight remain excluded.
- Shared fixture-first Check streams across Home/Search/Matchday/Details uses
  revision-fenced local opt-ins and bounded prior-found evidence. Candidate
  freshness and actual descriptor/token expiry remain separate; expired URLs
  never become Watch or bypass exact teams/squad/date/competition/status checks.
- Protected PR104/main83b1a44 publishes schema1 `/api/live/catalog` for exactly
  three reviewed profiles of ONE family. Bounded parallel complements preserve
  valid partial data/artwork; explicit empty/failure and native envelope checks
  retain independent official fixtures. Native fallback shares its original
  request clock.230backend tests and all8protected CI checks pass.
- Explicit playback/watchdog deployments preserve existing flags, original
  watchdog activation, all121notice IDs, budgets/leases and two-check rules.
  Native AS catalog-selection parity and trusted monitor-completion triggers
  pass186policy/runtime tests; real normal workflow_run execution/later cron
  verified. GitHub trigger diversity still depends on GitHub's platform.
-207focused current-source Catalyst tests plus one integrated outage regression
  pass with0fail/skip. Normal signed187/app+widget installed on Jet. Exact Cup
  Check→normal source picker→CS2 video passes90s ready-layer hold,83.82s media
  progression, same native player/item/attempt and actual fullscreen controls.
  CS1 failure is retained.45protected source hashes and user configuration
  remain unchanged; only six expected runtime cache slots update. Owned test
  runner removed; normal187 retained.
- Original187PiP gate FAILED/no system window at60sHome. Test-only correction
  observes actual start before Home and system Restore before app activation;
  it is compiled, not physically passed. No product PiP change is established.
 22:29UTC official refresh has no current supported football; finished Cup pin
  is invalid. Required PL/UCL/cricket and two truly independent supplies remain
  OPEN. AS1.9.98's new clock-only DLHD metadata lacks date authority; no weaker
  matching/security or invented date is admitted.
- Missing saved UCL follow-up replaced by bounded
  `fotty-remaining-live-acceptance`, ACTIVE through4Nov16:15Tobago, quiet on
  unchanged/no eligible live fixtures and free Jet only. Missing provider-alert
  chat follow-up was independently confirmed and recreated ACTIVE at15minutes,
  preserving prior-visible WD receipt ACK/no initialize/reset. These creation
  receipts do not prove later execution, inbox arrival or human reading.
- Direct cloud owner email is staged defaultOFF;214policy/runtime tests pass. Separate durable state,
  finite retries/leases/cutover/history preservation and sanitized operations
  notices. Owner destination verified29Oct23:06UTC; real address stays private.
  Sender onboarding remains unproved: proposed project domains absent from the
  connected account and sending-domain listing denied. No real alert email,
  sender/DNS change or email activation. Final reviewed source/tests/patch and
  remaining gates: testing/fotty187-broadcast-reliability/README.md and
  operations/Watchdog-Direct-Email.md. A tested fake binding is not delivery proof.
- Existing optional score-context patch remains separately staged and needs
  rebase/review onto83b1a44. It is not activated by this source-reliability work.

## 2026-10-29: Record partial Jet186 acceptance and separate broadcast failure from recovery

- Owner freed Jet and completed the XCTest approval. Physical consent controls,
  existing Matchday date jump, interest preview/browsing and complete native-key
  Cricket Search pass. Burst XCTest typing yields partial input in two runs;
  acceptance stays open, without proving a manual-user defect. Selector/lazy-List/key-case corrections
  are test-only, not production fixes or evidence clearing the original failure.
- Real exact-fixture navigation reached the normal Check streams action but no
  player opened. Playback/fullscreen/PiP are explicitly unqualified; a skipped
  test is not a pass. No source toggles, phone, FPL, multi-stream or TestFlight work.
  Original361-test evidence remains scoped;45 protected hashes remain unchanged.
- Bounded metadata shows the primary/mirror routes converge on a catalog serving
  HTML in a JSON string. Native already follows redirects; maintain schema and
  transport fences. Fixtures being verified cannot prove playable broadcasts.
  Confirmed discovery gaps:60s positive availability versus90s preflight, hidden
  Home alternative lookup, primary-only Details state and AS watchdog/native
  catalog-selection mismatch. Current open incidents predate today's check;
  normal delivery observer staleness and delayed owner comments are separate
  verified operational gaps, not proof of email/push/human receipt.
- Recommend bounded fixture-first availability, consumer/monitor contract parity
  and independently verified alert escalation before larger architecture changes.
  Stable availability must stay separate from expiring media descriptors; no
  false Watch, arbitrary source admission or weaker matching/transport policy.
  These recommendations are not implemented or deployed during discussion.
- Backend optional score-context patch remains staged pending its specific
  publication/deployment gate; it does not repair broadcast discovery. Quality,
  Report, widget/sync, current context and native playback acceptance remain open.
  See testing/fotty25-remaining-2026-10-29/physical186-summary.json and
  Broadcast-Failure-2026-10-29.md for scoped receipts.

## 2026-10-29: Stage remaining Fotty2.5 work and install private186 without launch

- Owner approves the remaining agreed REA product work and Jet iPad acceptance;
  phone, FPL, multi-stream and TestFlight remain excluded. Preserve the existing
  single-player/source engine rather than perform another broad rewrite.
- Reuse score facts already present in the admitted ICC fixture response:
  exact teams, innings, runs/wickets/overs, target and explicit Stumps/break
  context. Native data is optional, bounded and receipt/identity/format checked;
  malformed, held or stale facts cannot become current score authority. Home
  distinguishes explicit intervals from active play without changing underlying
  fixture status, source admission or playback timing. Legacy/missing context
  retains its documented existing behavior; no ball-by-ball guarantee is made.
- The admitted football-data six-league response supplies nullable CL goals and
  publisher timestamps. Stage only exact senior CL regular-time reported goals,
  clearly delayed with actual reporting time. Preserve null instead of0–0 and
  leave PL/FPL live-score fetching, quotas, cache and alerts unchanged. No new
  provider/account/purchase or paid API access probe. Current accepted terminal
  cricket/CL evidence joins a separate read-only matchContextCatalog, preserving
  conflict vetoes; finished score context never restores a playable listing.
- Add supported native single-player Auto/Data Saver without replacing/seeking
  its item or overriding Pause; keep fixed/unknown/Web choices truthful. Reuse
  the reviewed report/draft with concise playback issue classification and
  explicit sharing. Stage bounded background reminder reconciliation with OS
  scheduling limitations disclosed; repair expired-reminder rollback rather
  than claiming reliable push. Sports-only sync/widget acceptance remains open.
-361 selected current-source Catalyst tests pass,0failed/0skipped. Signed normal
  Release2.0.1(186), app/widget parity, strict signing/current Jet profile and
  existing App Group checks pass.45 protected FPL/multi inputs remain unchanged.
  In-place background installation preserves all34 current preference slots;
  no186 app launch or interaction occurred. Jet changed to the owner's reading
  app during compilation;18:22UTC shows the reading chapter changed, confirming
  background installation did not interrupt it. Access is requested once and
  physical testing awaits that answer; no takeover occurs.
  Phone177/shared121 and existing source choices remain untouched.
- A focused11-file backend patch is prepared against protected main70e8b10 as
  `2026-10-29.sports-context-1`, with215backend and181existing-watchdog tests,
  lint and both dry-run bundles passing. Nothing is published/deployed. Owner
  approval remains pending for protected publication, playback deployment and
  same-release compatibility rebuild of the already-active watchdog, preserving
  activation/leases/incidents/outbox/configuration. No monitor state reset or
  historical alert replay. The18:12UTC clean-candidate ICC check accepts59/59rows
  and verifies two ongoing Tests explicitly at Stumps; that is metadata evidence.
- Physical186 UI/navigation, actual decoded programme/source selection, native
  fullscreen/PiP/Pause/restore, quality and continuity acceptance remain OPEN.
  Installation, unit tests and dry runs do not establish TestFlight readiness.
  Current source/device plan: [Plan.md](../testing/fotty25-remaining-2026-10-29/Plan.md).
  Exact backend patch/scope/activation gate:
  [backend-plan.md](../testing/fotty25-remaining-2026-10-29/backend-plan.md).

## 2026-10-29: Install private185 on Jet iPad only

- Owner requests latest on iPad/iPhone, then narrows to “just install on ipad”.
  Phone177/shared121 left untouched; no TestFlight/publication/backend authority.
- Package tested return/discovery source as2.0.1(185), coherent app/widget and four
  Xcode configurations. No functional edits beyond the194-test candidate. One
  bounded signed Release build, strict signatures, current profiles containing
  Jet and existing sports group checked; CoreDevice installation reads back185.
- In-place install preserves all34 preference slots before any launch. No app
  launch, unlock, XCTest, source toggles, live-source/PiP or visual test.45 FPL/
  multi feature hashes unchanged. Local raw preferences, profiles, signed app,
  source copy, DerivedData/logs and keep-awake cleaned. Current physical gates
  remain open; install is not playback proof. Receipt:
  testing/fotty185-ipad-2026-10-29/README.md.

## 2026-10-29: Source-only return, broader Search and one interests editor

- Owner approves the first product batch after the five-product REA study.
  Source-only gate: devices, FPL/multi feature work, source settings, cloud/Git
  publication and TestFlight excluded; source version184 stays unchanged.
- Add an optional local last-live identity, defaultOFF under Privacy. A single
  owner creates a consume-once ticket; actual decoded-stage evidence confirms
  it. Only identity is retained, capped36h/8KiB; no source URL, credentials,
  artwork, autoplay or Fotty history sync/explicit-backup payload. OS backups
  are not excluded by a UserDefaults promise. Forget/opt-out/Stop/replacement
  revoke callbacks; leaving single panes revokes synchronously. Pure eligibility
  needs current exact catalog identity and fresh explicit LIVE. Existing Home
  clock/Privacy tasks prune old records without cancelling a newer owner ticket.
- Home shows one compact clearable return card only without a retained viewer.
  It rechecks on tap and uses fresh normal discovery. Names reflow, controls stay
 44pt, real paired badges remain; non-match events use sport art instead of a
  fabricated away-team badge. Native visual acceptance remains open.
- Search adds a14day source-free projection from existing accepted snapshots,
  retaining envelope/lane/row observation freshness and independent CPL receipt.
  Publisher last-change time cannot hide a freshly observed unchanged future
  fixture; stricter LIVE metadata is unchanged. Hidden conflict/terminal evidence
  and exact dated-pair/squad score cancellation take precedence. No new fetch,
  endpoint, feed, cache admission or Home72h change. Existing cooperative index,
  recents, follow shortcuts and truthful schedule-only actions remain.
- One Home interests editor previews the current vetted lineup, browses sports
  without following them automatically, and uses additive sport/competition/team
  choices. Settings/onboarding/Home use that editor and existing stores. Selection
  summary is bounded; zero-interest fail-open and save/volatile errors remain.
-194 current-source Catalyst tests pass,0fail/0skip;32 source-membership tests and
  native membership/version checks pass. Two initial new-test failures used
  contradictory fixture identities; repaired the fixtures, retained quarantine
  assertions and shared production identity rules. Zero-test runner output was
  rejected and corrected. Added freshness/cancellation/clear/expiry/rapid-context
  regressions.45 protected FPL/multi files stay unchanged. Final native Release
  compile/cleanup evidence: testing/product-return-discovery-2026-10-29/.
- Physical UI, current native playback and184 fullscreen/PiP remain separate
  owner-deferred gates; compile/unit evidence does not close them.

## 2026-10-28: Repair interrupted single-native preparation; install184 only on Jet

- Owner approves CNC/CS review and Jet native playback/fullscreen/PiP repair gate;
  phone, FPL, multi-stream and TestFlight excluded. Owner later reclaims Jet for X,
  declines takeover and requests just installation. Signed normal Release184
  installs without launch;34/34 preferences preserved, version readback verified.
  No184 physical playback pass. Phone177/shared121/source defaults unchanged.
-183 live World Series CS1 decoded correct programme>90s; fullscreen Pause,
  inline return, paused reentry and Play succeeded. PiP advanced>60s in Clock, then
  CoreMedia-12312/segment_uri_changed failed before completed round trip. Actual
  observation and native records corroborate it; no claim that Fotty caused the
  HLS inconsistency. Independent relay review finds no proven relay defect.
- Confirmed app defect: retry retired relay before descriptor await; background
  cancellation left apparently-ready old item. Foreground resumed it under a new
  attempt, stalling80s.184 owns a single-native preparation lease, detaches retired
  item and defers/resumes preparation across background/foreground or explicit
  Play, including already-backgrounded starts. Pause retains intent; cancellation,
  replacement and cleanup revoke lease. Actual expiry, late-response ownership
  and transport retry budgets remain enforced. Single-only fences preserve multi.
- Seven new preparation regressions; final native75pass/0fail/0skip. One new-test
  placeholder label corrected to admittedCS4; no production admission or assertion
  weakening. Separate CS117pass/0fail/0skip covers explicit+24h rejection, corrected
  same-ID refresh and squad/tolerance/conflict cases.
- CNC's new HTTPS host returns empty25byte HLS with advertised and relay-safe
  headers, zero variants/segments; final no-cache recheck01:28UTC still empty.
  No unqualifiable host/header exception added. CS dates official current NHL pair
 24h late in catalog and same-ID metadata; official7day schedule lacks rematch.
  Preserve exact-date rejection, no invented shift. These are bounded upstream
  blockers, not repaired bindings or proof of permanent global outage.
- Compiled official Shaka5.3.2 REA supports per-delivery header authority, bounded
  abortable retries, advertised timeline and same-media presentation. Artifact
  hashes, partial-graph limits and source correspondence retained; static web
  evidence is not native PiP proof. No library/broad rewrite imported.
-314 build inputs and43 protected hashes match; strict signature, Jet profile,
  main/widget184 versions verified. Independent read-only review finds no further
  defect. No Git/cloud/TestFlight. Redacted receipts:
  testing/fotty184-source-native-2026-10-28/. Live184 round-trip/longer reliability
  and PL/UCL/cricket qualification remain pending. Owned output/private data and
  temporary keep-awake cleaned at exit.

## 2026-10-28: Install discovery candidate183 on Jet; keep unavailable live gates open

- Owner authorizes private Jet install, focused failure repairs and live-source/
  single-playback checks; phone, FPL, multi-stream and TestFlight remain excluded.
  Normal Release182 then183 installed in place with strict signature/profile and
  version readback;34/34 existing slots match before each launch,19/19 selected
  personal/source slots match at exit. Seven enabled providers remain unchanged.
- AS1.9.82 advertises plaviohd-football separately from legacy generic live-sports.
  Select the unique reviewed advertised catalog, retain old-manifest fallback,
  key generation/cache and revalidation by that same selection. No wider scan.
  Seven new offline regressions; compiled AS run67pass/1physical skip/0fail.
- Official Washington Capitals–Philadelphia Flyers28Oct23:30UTC is current;
  CNC advertises exact dated Capitals–Flyers. Add only those two corroborated
  source-local aliases, retaining squad/date/league/conflict restrictions.
  Four new regressions; CNC/optional-policy run46pass/0skip/0fail. A separate
  speculative hockey-eligibility hypothesis was disproved and fully reverted.
- Real normal Check streams on182 missed both CS/CNC. On183 CNC reaches its two
  stream entries but rejects both: one external/donation entry and one changed
  media host/path/header contract. No media fetch or security expansion follows.
  CS publishes the pair24hours late and its live catalog lacks tonight's pair;
  retain the exact-date guard rather than inventing a date. Provider availability
  and a transport compatibility change are distinct from the repaired name join.
- Final complete AS football5rows are future/generic at29Oct00:43UTC; cricket20
  rows do not establish a supported current programme. ICC59/59 shows Tests at
  STUMPS. No decoded90second/current-programme/fullscreen/Pause/PiP/source-switch/
  failover or PL/UCL/cricket qualification is claimed for183. These gates remain
  pending external delivery compatibility and real eligible windows. Generic
  channels and metadata success cannot substitute. No TestFlight readiness claim.
-314 final build inputs match snapshot/workspace;43 protected feature hashes
  unchanged. Landscape/Home-Football/keyboard capture OFF restored; owned output,
  private device/prefs/profiles and keep-awake cleaned at exit. Redacted install,
  quality, official schedule and descriptor receipts live in
  testing/fotty183-discovery-playback-2026-10-28/README.md. Source-only predecessor
  remains dated separately; no Git, cloud or source-default change occurred.

## 2026-10-28: Separate independent source discovery, fresh candidate evidence and playback

- Owner requests discovery and correct stream catalogs as well as recovery after
  the shared publisher closure. Three-agent Stremio/Nuvio/Jellyfin REA research
  informs independently implemented mechanisms; no upstream source was imported.
  This is a local source gate: devices181/177, source defaults, FPL/multi-stream,
  cloud/watchdogs and shared121 remain unchanged. No release/deployment authority.
- Reviewed typed plans keep independent providers available without master
  catalog source entries. Complete exact MatchHub identities do not wait for
  master lookup. Preserve Score808-only shared/direct lanes and18second bounded
  append-only discovery; retain sport/date/squad/competition/conflict admission.
- CS/AS force fresh resources on explicit single checks; eligible cached missing
  capability/empty descriptors get one targeted revalidation. Ephemeral exact
  event/stream bindings retain short freshness and cricket ordinal/Testday
  context, excluded from persisted session JSON. Empty catalogs expire sooner.
- Bounded foreground optional-provider checks feed a24-record candidate index,
  not a LIVE assertion. Two lanes/call,8seconds,90second scheduling/cooldown,
 24/hour and96/day preflight-start caps; manual checks remain independent.
  Retain due time/fixture rotation across contentRevision replacement. Generation
  fencing and awaited disable invalidation prevent late/cache resurrection.
  Coordinator-owned manual lookup/playback also revokes the foreground metadata
  task; recheck eligibility after registry awaits to avoid duplicate resolution.
- Single-stream bound CS/AS descriptors can renew once inside existing native
  startup budgets. Keep selected UUID/opaque label; only fresh admitted delivery
  fields replace transport grants. Stable upstream keys remain exact; signed
  delivery-key rotation must retain unique choice/origin/path. Known expired
  media cannot replay after nil renewal; metadata TTL is a different fact.
- Typed current causal HTTP/error facts prevent401/403/decode/unsupported retry
  loops. Strict evidence is explicit-single opt-in; multi keeps legacy defaults.
  Injected ViewModel checks caught Pause being ignored during suspended metadata
  negotiation. Pending intent now respects Pause; explicit Play resumes same
  pending work or reopens only that source after a discarded paused response,
  without resetting automatic native/failover counters.
- Local checks, exact snapshot hashes, test outcomes/skips and the unsigned iOS
  Release compile are retained in testing/fotty-discovery-catalog-2026-10-28/.
  The owned temporary snapshot avoids a Documents source-read stall without
  changing Mac permissions. One omitted shared JSON fixture was included before
  its successful rerun; no source guard weakened to repair tests. Physical live
  PL/UCL/cricket90second decoded/programme/control/failover gates remain pending.
  Current candidates, unit passes and earlier181 playback are not that proof.

## 2026-10-28: Repair provider watchdog detection and verified owner-targeted delivery

- Owner requests provider failures reach us proactively; keep FPL/multi-stream,
  devices and TestFlight unchanged. Publish only18watchdog source/test/workflow/
  operation-doc paths through protected PR92/main eb1c283 and focused2-path cadence
  PR95/main70e8b10. No administrator bypass; Web/CodeQL/secrets/workflows/watchdog
  CI pass. New targeted bot comments use existing GitHub issues: verified owner
  assignment, stable event marker, ambiguous-write retry and retained pending
  state before recording submission. Failure makes Actions fail; recovery cannot
  overtake an undelivered confirmation.114 old issue-only notices do not replay.
- Collection15min/two matching failures/two fresh positive recoveries; exact
  verified closure immediate. Empty/source-less catalogsUNKNOWN cannot erase
  outages; stable aggregates catch alternating fatal causes. Add admitted AS
  football/cricket, Carabao scope and one exact-current CS descriptor-shape sample.
  No media/native decode, source trust/settings, telemetry, new credentials or
  paid AI jobs. Caps960provider+288fixture/health reads/day.10s probe deadline is
  not proof a native12s request is incompatible.
- Preserve old schema1 counters up to historic3 under current threshold2 without
  mutating history. New config resets streaks on fresh observations only. Real
  workerd old-storage equality, old GitHub notice delivery, suspect resets,
  cadence carry-over and active-lease tests pass.165offline+16runtime pass with
  no skips; repeated gates overlap, not additional unique counts.
- Watchdog4316bd15/config2026-10-28.admitted-metadata-2 retains wire namespace,
  original11Oct activation, Durable Object and114original notice IDs/times. Safe
  source default0 cannot override explicit production1/original activation under
  keep-vars. Compatible playback-version drift now alerts separately while
  finite notices continue; incompatible observer/config wire remains blocked.
  Real scheduled collection: 28Oct22:30:36.405UTC attempted/22:30:38.028UTC committed, next22:45:36.405UTC;114original notices unchanged/no overflow.
- Actual bot canary40778349200 assigns jetboss and posts one mention on clearly
  synthetic issue93; no provider ledger mutation. Firstdelivery1/replay0/API4→1,
  exact commentreadback then testclosed. WD-a78a583c69b1338ded7c9937 reported here,
  read_thread verifies chat append beforeACK; restarted reader quiet. Normal
  observers40778605662 and40778983593 pass/pending0. Chat automation
  fotty-provider-failure-alerts ACTIVE/15min/default notifications on this chat.
  It verifies prior WD messages beforeACK, retains pending notices and checks
  stale collector/normal observer, failed delivery, capacity and revision drift.
- Chat bridge needs Mac/app; GitHub targeted path is cloud independent. Intended
  schedules are not an SLA. Email/push/human receipt is not proven; no token scope
  or OS/account preference expanded. Metadata is not decoded playback proof.
  All313 native181 input hashes unchanged; no device/FPL/multi/TestFlight changes.
  See testing/watchdog-owner-alerts-2026-10-28/README.md and
  operations/Watchdog-Owner-Alerts.md. Preserve durable alert state; remove only
  owned temporary checkout/log/runtime/keep-awake output after qualification.

## 2026-10-28: Restore Cup discovery and actual native CS2 football on Jet181

- Owner requests working football and Mac keep-awake through completion;
  separately approves EFL activation/deployment and same-code watchdog update.
  Named Jet gate supersedes its old175 hold. Phone/FPL/multi untouched; no TestFlight.
- Streamed's three catalog mirrors share a closed publisher. Exact closure
  reason/start unknown. Add isolated official EFL Carabao scope, with explicit
  UTC/period/scope/count/receipt fences and durable retention. Cup stays separate
  from PL; explicit interest does not migrate preferences. Existing Score808 can
  check verified source-free football. AS same-ID explicit UTC metadata no longer
  relies on closed Streamed. Score808 absent visible defaults true, proved by
  shipped calendar normalizer; false/null/malformed/identity guards retained.
- CS26Oct /api/manifest.m3u8 alias was rejected by old literal validation. Accept
  both exact paths across admission/nested/profile bindings, preserve raw query,
  and explicitly relay headerless aliases. TLS/public-IP/redirect/header/nested
  restrictions retained; HTTP8008/2122 blocked; no arbitrary trust expansion.
- Protected PR91/mainc3ebfa publishes only eight backend paths. Source
  2026-10-28.efl-cup-1/Workerb3ff08d7 verifies eight Cup fixtures. Isolated67 tests,
  lint/dry-run/CI pass. Separate watchdogd8c5e8cf preserves activation/budgets/
  incidents;108tests/exact-revision observer pass. GitHub issue88 did not become
  owner triage; direct chat/push bridge remains absent. Observer pass is not
  source health or decoded playback.
- Normal Release181 Home/details/Check streams gives seven choices. CS1 fails404
  twice; automatic recovery selects CS2/PPV Native FullHD. Actual Sky Sports
  Liverpool–Chelsea1–1 clock64:50→76:20 advances >10min; independent EFL68′ status
  corroborates programme. Sources open/close, same-attempt native fullscreen,
  pause/resume and landscape pass; leave playing. Decoded progress2718ms. No
  audible/PiP/all-source/PL-UCL qualification; empty AS/Score808 media403 remain.
- Fresh units:112fixture/lookup cases covered, corrected invalid new test data/
  21overlapping rerunpass; AS52+one skip; CS/relay/Score808185+one skip. Catalyst
  units separate from physical normal-app proof. All313 inputs match181/15changes
  vs178/298unchanged;42 FPL hashes and multi inputs unchanged;34prelaunch and
 25post-playback config slots preserved. Earlier179/180 lack of decoded proof
  remains honest. Clean owned gate/keep-awake. Receipts:
  testing/fotty181-playback-recovery-2026-10-28/README.md;
  audit/Fotty-Missing-Liverpool-Carabao-2026-10-28.md.

## 2026-10-25: Repair nine confirmed core defects in order and verify private Jet178

- Owner approves the nine audit findings in reported order, then Jet iPad tests.
  Keep the phone, FPL and multi-stream unchanged; no TestFlight or publication.
  Block continuity configuration, queued application and publication against
  volatile fallback storage, preserving accepted journals/receipts/widgets.
  Require admitted terminal authority before fixture merges remove provider
  listings; replace failed/retired single-stream owners while retaining healthy
  paused/fullscreen/PiP owners. Share Home/catalog squad-aware deduplication.
- Add only verified Real Sociedad de Fútbol/Udinese Calcio aliases. Validate
  widget rows before bounding or badge work; unsupported local sports cannot
  poison valid rows. Publish durable local widgets despite sync journal quota
  errors without pruning tombstones or enabling cloud sync. Local interests
  include Darts (13); existing sync/Handoff/planned-match/widget wire scope stays
  at12. Filter local-only interests before sync publication and preserve them
  through remote reviewed-sport changes. Search labels fill measured equal-height
  cells without changing artwork, typography or grid actions.
- Native coverage spans363 unique selected cases:362 passed on the first run;
  one obsolete terminal-reconciliation assertion was corrected, followed by an
  affected40/40 rerun. Do not add overlapping counts. Eleven web tests and the
  generated catalog coherence check pass. Signed normal Release2.0.1(178) is
  installed on Jet. Physical XCTest executes zero cases after a Touch ID
  authorization timeout; this is not an automated device pass.
- Separate manual Jet evidence covers Home/Search/Settings, local Darts choice
  restored afterward, Matchday/details, landscape and the existing source sheet.
  Native fullscreen, paused reopening, PiP background playback and restoration
  pass. All23 protected preference slots match, including six FPL keys, source
  enablement and syncOFF;59 protected FPL/multi hashes match. Phone177 untouched.
  No new source90s/programme qualification, audible-output, physical AX, measured
  performance or real cloud-retry acceptance is claimed. No Git/cloud release,
  source activation, tester changes or TestFlight. See
  audit/Fotty-Nine-Core-Fixes-2026-10-25.md and
  testing/fotty178-nine-fixes-2026-10-25/README.md.

## 2026-10-25: Install177 on the owner's iPhone; separate manual UI evidence from blocked XCTest

- The owner lifts the phone175 hold for deployment and UI testing only. Fresh
  identity confirms Jelani's iPhone15ProMax/27.0.1. The existing Xcode app had
  updated to27.1 but required system device components; completing Apple's normal
  setup resolves initial CoreDevice/Device Hub startup stalls. No simulator boot,
  pairing reset, account/security change or other-device test.
- Build current unchanged177 source with27.1/jobs1, strict signatures, app/widget
  version coherence, in-place install/readback and normal launch.310 application/
  test/project hashes match. The signed phone binary differs from earlier Jet177
  because its compiler changed; retain exact identities in the phone receipt.
- Focused UI test build passes, but iOS automation approval times out before any
  requested case executes. Stop its diagnostic/password wait; do not count the
  infrastructure failure as an app defect or a test pass. Restore normal Release.
- Existing Device Hub manual controls verify Home/three-column grid, Matchday,
  Settings/Appearance and Search with the full software keyboard. Preserve the
  transient query without submission. Match-details medium sheet is observed;
  full details/player/source/AX/performance gates remain open. Stop remote input
  when owner use in another app becomes visible; owner explicitly says leave the
  phone alone. Search's uneven two-line sport
  tile height is a small documented visual follow-up, not changed in this gate.
- All12 present protected configuration keys, including the whole plugin-state
  dictionary and FPL connection/confirmation, match the phone's own snapshot.
  No private values are exported or Jet preferences copied. Remove only the newly
  owned test runner/temp output. FPL/multi-stream unchanged; no new-source
  qualification, Git/cloud publication or TestFlight. See
  testing/fotty25-ui-phone-2026-10-25/README.md.

## 2026-10-25: Finish the core UI candidate and verify Jet177, keep iPhone175 held

- Use Apple/reference-backed actual-root comparisons rather than another effects
  dependency. Repair intrinsic Home/Matchday headings, compressed narrow Watch,
  true-empty Home, Search/Settings/details accessories and single-player sheet
  navigation/scrolling. Preserve native controls, art, badges and all existing
  source/transport/default/consent/FPL/multi-stream behavior. Neutral More
  broadcasts does not manufacture a live match claim.
- Fresh Catalyst broad392pass followed by affected108/11 reruns; these overlap.
  Thirty-five actual-root captures/9 retained pairs bind to57 focused inputs. Their
  pad idiom, SceneStorage and glyph limits remain explicit; no golden rebaseline.
- Owner lifts Jet hold for UI only. Four normal-data physical journeys pass:
  core navigation, Sources bottom/Close and player Details, landscape composition,
  and standalone catalog details. All six roots have real Jet captures. Correct
  test assumptions about restored query/focus, nested native tab AX wrappers,
  inline Details and rotated app-bounds screenshots instead of rewriting working
  app code. Whole-display landscape captures preserve TIFF orientation8.
- Restore signed normal177, remove only the newly owned test runner and temporary
  gate. Manager identity/confirmation, seven source choices, dark appearance,
  sport interests and Recent history preserved; two derived FPL caches may
  refresh normally. Four journeys are UI proof, not decoded source qualification,
  native fullscreen/PiP acceptance, VoiceOver/large-text or measured performance.
- iPhone175 remains untouched; source campaigns remain metadata-only, with their
  original expiries. No source-setting changes, dependency, Git/cloud publication
  or TestFlight. See audit/Fotty-2.5-UI-Completion-2026-10-25.md and checked ledger.

## 2026-10-25: Adopt reference-backed UI evidence without changing owner175

- Owner approves Apple resources, real-product references and strict visual
  comparison. Read current Apple Layout/Playing Video and public TV journey
  guides; distinguish official kit listing/Mobbin landing access from inspected
  design-file layers or operated journeys. No paid account or new UI dependency.
- Add a checked six-screen contract: approved concept hashes,39 focused UI/shared
  dependencies, five historical component-study hashes and specific open native
  checks. The no-dependency read-only checker rejects stale/mislabeled evidence;
  it never approves releases/installs or attests compiler inputs. Preserve the
  original pixel baselines and their separate explicit-review process.
- No newly confirmed screen defect warrants a redesign. No production/test Swift,
  device, FPL/multi-stream, source setting or TestFlight change. Prior328tests and
  unsigned compile are historical receipts, not rerun claims. Both175 devices
  stay frozen; actual screen/keyboard/safe-area/AX/player acceptance remains open.
-60 evidence-tool tests pass. Actual pack integrity passes; strict completion
  correctly fails on six pending native-screen gates. Prior21-file source digest
  and all10 accepted baseline PNG hashes match. No heavy build or owned output.

## 2026-10-24: Finish the approved core UI source implementation; keep175 installed

- Owner expands the focused2.5 UI patch to the accepted iPhone/iPad experience.
  Home uses a bounded1.55:1 wide overview, grouped/separated lazy rows, centered
  sport art and readable names. Narrow/AX reflow is intentional, not text scaling
  to force desktop geometry. Correct the real206pt compact-grid regression while
  retaining the existing190pt limit, readable type/art and44pt touch convention.
- Matchday stays a personal plan; Search retains native input/owned results;
  Settings gets calm native groups and width-aware/RTL accessories. Move the
  existing details Watch/countdown before long help. Bound the follow action;
  correct obsolete no-cloud-sync copy without changing any consent/sync behavior.
- Single player keeps video-first iPad and retained native fullscreen/media owner;
  quiet phone identity/controls and joined source rows are single-only opt-ins.
  Existing native tabs, multi branch and FPL code stay unchanged;52 hashes match.
- Fresh Catalyst328checks/0fail, unsigned iOS Release pass,21 renders; first run found
  and repaired the grid height. These are not full iPhone/iPad screenshots or
  physical Dynamic Type/VoiceOver/playback acceptance. Do not silently bless the
  original10October pixel baselines. Both175 devices remain untouched for feedback.
- Review Apple kits/Mobbin/selected GitHub references; no subscription, framework,
  plugin or global skill install. UI receipt separates implementation from the
  still-frozen signed/device gates. No Git/cloud/TestFlight publication.

## 2026-10-24: Implement the five Fotty2.5 source workstreams; keep device175 frozen

- Owner approves all five in order, not another install. Registration/defaults/
  labels/fixture scope/dispatch now use one finite reviewed catalog. Adapter
  admission stays source-specific; no arbitrary manifests or trust expansion.
- Home/Matchday single Watch uses scene-owned incremental discovery under the
  existing18s collector. Preserve sport-aware bottom feedback, exact current
  fixture/generation fences and first mount; append later alternatives without
  reordering/reloading the active owner, Pause, native fullscreen or PiP.
  Existing aggregate callers keep their API; menu/filter opening is presentation.
- Inline read-only context, visible existing More actions and task-grouped
  Settings implement the native contracts without a new theme, EPG inference,
  changed source defaults, duplicate reminders or lost badge/sport identity.
- Measure before optimizing: separate catalog-owned Search preparation from
  query results; use the same dedup accumulator in32-row Home-only cooperative
  batches; exact-URL badge failures get2s/256-entry memory-only retry cooldown.
  All intermediate projections remain unpublished on cancellation/staleness.
- Reuse canonical actual Stremio2.0.7 REA evidence; native2.1 behavior/decoder
  policy remains unknown. No GPL player dependency, copied proprietary UI,
  installed decompiler, device interaction, publication or TestFlight.
- Preserve both device175 installations and all51 FPL/multi-stream source/test
  hashes. Restrict existing three source follow-ups to metadata-only until the
  owner ends the hold, without extending their original windows. See the dated
  implementation receipt for local tests/measurements and still-open device gates.

## 2026-10-24: Prioritize Stremio/REA-inspired Fotty2.5 without disturbing175

- Owner shifts full product priority to Stremio2.0/REA and a coherent Fotty2.5
  milestone. Keep175 owner/Jet installations frozen for next-day feedback;
  FPL/multi-stream paused, no new install/TestFlight/cloud/Git/spending gate.
- Actually inspect official native Mac2.0.7(22) with REA6.4.0: artifact inventory,
  extraction, plist and Mach-O records retained in1.3MB canonical evidence pack.
  Main image links UIKit/AVKit/AVFoundation/VideoToolbox/KSPlayer. Imports do not
  establish selected engine, source support or speed. Native2.1 announcement is
  separate; deep native providers/runtime/code evidence remain unavailable.
- Roadmap order: curated modular source definitions; complete bounded single
  source journey; purposeful browsing/planning; native phone/iPad contracts;
  measured responsiveness/full acceptance. Do not re-list162/165/171/173 work as
  missing. Keep existing identity, relay, Pause/fullscreen/PiP and native controls.
- KSPlayer is not adopted: current license/platform constraints and physical-iOS
  build/support must be resolved only if a genuine AVPlayer decoder gap warrants
  a bounded comparison. No engine swap for upstream502 or timing/token failures.
- Apple skill/HIG governs previews before substantial UI changes. Existing audit
  holds evidence, acceptance contracts and remaining questions. No runtime edits
  or version bump. Secret scan passes;449MiB temporary artifacts/awake helper
  removed,11GiB free. Keep only intentional small canonical receipts.

## 2026-10-24: Extend private175 to Jelani's iPhone for owner testing

- Owner asks for the same build on his iPhone and will test25October/report
  findings. Target only fresh live Jelani's iPhone15ProMax/27.0.1, not archived
  April identity or another phone. Normal developer pairing restores reachability;
  no service reset/unpair/security-setting change. Existing app is125.
- Rebuild/sign175, verify app/widget profiles, strict signatures, membership,
  versions and frozen source, then install in place/read back/launch. One normal
  process survives a later read. No UI/playback campaign or TestFlight claim.
- All nine private FPL values/three saved source switches remain unchanged after
  launch;52 protected source hashes match. AS/SV/FS stay OFF; CS stays ON. Do not
  copy Jet settings or add a phone to scheduled Jet-only qualification.
- Provenance and cleanup: release175. Remove371MiB owned output, preferences,
  bundle, verification folder and awake helper.11GiB free; encrypted OS swap is
  observed, not deleted or proven the sole free-space cause. Leave owner testing.

## 2026-10-24: Install private175 on Jet without qualifying new sources

- Owner requests iPad deployment for personal testing. Allocate coherent175,
  build signed normal Release with official Xcode, compare frozen pre-build source,
  install in place/read back/launch on Jet only. No shared publication/TestFlight.
- Includes approved SV timing and AS cricket adapters; prior297 units/3physical
  skips remain the focused policy receipt. No repeated unrelated playback tests.
- Strict/deep signatures, membership/version checks and normal process readback
  pass.52 protected hashes, four private FPL values and six existing source
  switches remain unchanged; SV/FS OFF. No source enablement or live pass claimed.
- Source receipt, exact install scope and remaining windows: release175/audit.
  Stop timed-out preview; remove owned output/preferences/bundle/awake helper;
 15GiB free. Leave iPad to owner testing, phones/FPL/multi-stream untouched.

## 2026-10-24: Stage source-local StreamViX timing reconciliation and AS cricket

- Owner approves StreamViX timing repair and AS cricket/pending-source Jet live
  qualification. No phone, FPL, multi-stream, cloud/Git publication or TestFlight.
- Reconcile original full-date GMT with canonical UTC or uniquely verified Rome
  conversion only; DST ambiguity fails closed. Original PL/UCL teams/competition,
  literal advertised target, catalog/meta and collision/conflict fences remain.
  SV1–SV6 is a separate default-OFF module, using reviewed fresh HTTPS443 HLS and
  the existing relay. Empty/expired placeholders remain rejected.
- AS cricket owns separate catalog/cache, exact UTC, known format and ordinal/
  squad/day fences. Support reviewed T20I and Test Day1 only; later Test days,
  unknown/ODI/T10 formats and football-ID fallback cannot invent cricket joins.
- Focused fresh Catalyst297pass/0fail/3physical skips, membership/version checks
  pass.52 protected hashes unchanged. Normal Jet174 is not replaced or interacted
  with. This is source readiness, not a new working feed or physical acceptance.
- Read back bounded thread follow-ups for PL/pending through26Oct, AS27–28Oct
  and UCL3–4Nov. Each needs fresh live facts, available Jet, actual90s decoded/
  correct-programme/normal-picker/control proof; restore unqualified switches and
  disable at its end. See dated source audit. Clean all owned build/awake output.

## 2026-10-24: Private174 adds default-OFF Flix integration without claiming playback

- Owner approves Flix-Free PL/UCL/cricket qualification and Jet use, then another
  AS-like source search. FPL, multi-stream, phones, backend and TestFlight stay alone.
- Fixed public manifest/genre catalog uses all three reviewed pages, not ignored
  search. Exact sport/teams/squad/UTC and conflict vetoes precede streams. FS1–FS6
  owns the optional sixth module and finite hashed attribution; existing choices
  remain intact. Only reviewed headerless same-origin HTTPS443 HLS uses the
  ordinary guarded relay. No player, ranking or trust exception is added.
- Physical lookup caught the initial parser rejecting the real TV hint/video
  envelope. Decode it narrowly and corroborate target IDs and released UTC against
  the description, retaining malformed/conflicting siblings. Synthetic network
  fixtures now reproduce the actual envelope.306 units pass/3physical-only skips;
  final flagged physical helper compiles; source/version/signature checks pass.
- Independent ESPN status confirms current Lazio–Parma for a general-football
  compatibility check only. Repaired FS1/FS2 return upstream manifest502 and zero
  frames; another FS2 lookup fails before media. No source/90s/programme/picker/
  PL/UCL/cricket pass or activation. Do not force headers/security or call this
  permanent provider failure. StreamViX's sampled PL time conflict holds that lead.
- Signed normal174 is installed/read back/launched on Jet.52 protected hashes,
  four FPL values and five source switches match; FS remains OFF. Source/build/
  device receipts and next live-window gates: release174 and dated source audit.
  Clean owned output/awake helper; no Git/cloud/distribution changes.

## 2026-10-24: Private173 ranks recent single-stream startup, not lifetime volume

- Owner authorizes fast/reliable source ranking and Jet testing, plus research
  for AS-like alternatives; FPL, multi-stream, phones and TestFlight stay alone.
- Explicit new-single entry opt-in avoids changing shared models, which also
  initialize as `.single` for Watch Two. Initial choice/failover use seven-day,
  at-most12 decoded startup samples, median500ms buckets, confidence capped3,
  actual direct-media contracts and late last-good ties. Fresh legacy average
  counts as one weak observation. No AS hardcode, filtering, cross-fixture
  negative bans, active/manual-owner reload or security/admission change.
- Nine store/five integration regressions; focused Catalyst332pass/0fail/one
  intentional soak skip. Membership/versions/identity/signature pass. Signed
  normal173 installed/read back/launched.52 protected hashes/four FPL values/
  five source switches unchanged. Receipt/source details: release173.
- Normal Watch auto-selects AS1 on live Lazio–Parma:1,412ms discovery and1,933ms
  decoded start; correct programme/picker observed. Owner's subsequent manual
  comparisons record AS1.3–1.4s. Concurrent device use/stale-black previews mean
  no controlled90s/fullscreen/PiP pass; no speculative presentation repair.
- Flix-Free's public dated metadata/HTTPS-HLS descriptors are the best new lead,
  not proof of current coverage, independent upstream or native reliability.
  Nebula lacks public no-config descriptor evidence; StreamSports99 is currently
  external-player/self-hosted. No new feed enabled. See dated source audit.
- Remove owned temporary output/preferences/screenshot/source bundle/awake helper;
  leave the iPad to owner testing. No shared publication/deployment/distribution.

## 2026-10-24: Private172 restores CS discovery; live Premier League hold stays open

- Owner authorizes comparing the working adapter, fixing the iPad rejection and
  testing live Premier League on Jet; retain UCL, FPL, multi-stream, phones and
  TestFlight boundaries. AS is the owner's fast/reliable-source benchmark, not
  authority to change default selection in this repair.
- Retained140 source has the same prefix/length/character policy and metadata
  ID handling. Optimized Jet172 reports character rejection without a forbidden
  scalar. Replace the bound-method predicate with the single explicit scalar
  walk also used for diagnosis; do not call this a proven Apple/compiler bug.
  Actual Jet discovery then returns exact matches and ordinary picker CS rows.
- Bounded advertised search and reviewed legal-name hints recover fixtures
  beyond100-row catalogs; preserve completed conflict evidence, exact squads/
  date/sport and all transport/media fences. No new source/admission exception.
 161 focused Catalyst tests pass, zero failures/skips/runtime warnings, including
  exhaustive ASCII/Unicode and real-ID ordinary/search regressions; UCL retained.
- Six repaired-build requested-CS PL checks all skip, not pass. Actual Streamed
  segments return403; Daddy variants show probe timeout or CoreMedia changed-
  segment failure; PPV native failure yields only brief CS2 fallback video.
  Last explicit CS2 run cannot list it after11.192s stream-list timeout. AS
  succeeds in1.627s in that same discovery. No fallback qualifies the90s hold.
  Current other-variant playlist checks do not justify blind timeout/profile
  changes. PL sustained playback and live UCL remain OPEN; see release172.
- Normal signed172 installed/read back/launched. Frozen1140-file comparisons
  pass;44 source hashes/four FPL values/five existing switches unchanged (all ON).
  Remove the owned runner/scheme/build/results/preferences/snapshots/awake helper,
  preserving unrelated artifacts. No real Git/publication/cloud/release changes.
- Ranking discussion is read-only: local coarse family+host success/startup/
  recency and last-good context, then legacy-provider tie priority; not a current
  fastest-start race. Do not infer an individual winning score from static code.

## 2026-10-24: Jet171 native fullscreen acceptance passes in portrait and landscape

- Leave correct production code unchanged. Extend physical coverage using an
  observed source in the real Home picker, normal scroll and60s preparation;
  reject fallback/Web routes. The previous25s/first-two-visible setup was too narrow.
- CS6 Rayo–Elche reaches real native720p. Initial run passed Pause/paused Done/
  re-entry/Play, then lost the auto-hiding Close button during redundant test AX
  reads. Repair only the harness: ownership/rate admission first, immediate real
  system-control tap, broad diagnostics on failure only; preserve post-action checks.
- Fresh portrait67.199s and landscape76.181s tests each pass, no failures/skips.
  Actual Apple Pause/stable time/paused return/re-entry/Play/Done/inline progress/
  source controls preserve one player/item/attempt per run (20/21 receipts).
  Correct RAY0–3ELC programme observed. No PiP/audio/soak/provider-wide claim.
- Keep video-first layout; normal signed171 restored/installed/read back/launched,
  original orientation restored, runner removed.46 protected hashes/four FPL values/
  five source states unchanged; AS OFF. No phones/FPL/multi/cloud/TestFlight work.
  See release171 follow-up receipt; remove only owned output and awake process.

## 2026-10-24: Private171 makes iPad single-player video-first; native device gate stays honest

- Replace only the iPad single-player companion rail with the largest two-axis
 16:9 stage, compact badges/title and outside-media Sources/Details dock. Native
  details sheet and compact accessible controls; phone/two-player paths unchanged.
- Keep the existing scene-retained media owner, source selector and same-player/
  item AVKit fullscreen action. Sheet/rotation presentation does not load a source;
  explicit alternate selection still connects to that delivery. No overlay steals
  WebKit controls; no source, recovery, FPL or multi-stream refactor.
-62 local tests pass; real Home presentation test passes on Jet in57.175s:
  rotation, Details/Done, Sources cancel/reopen/selection and Close. Real TNT
  programme observed; landscape AX stage1118×629 in1180×820 with dock outside.
  Fresh physical native-controls test correctly skips after Web default and two
  non-advancing native alternatives. AVKit device acceptance remains OPEN; no
  source-wide failure/PiP/audio/decoder-soak claim. See release171 for harness history.
- Normal signed171 installed/read back/launched;45 protected hashes, four private
  FPL values and five source states unchanged. UI runner removed. AS OFF/Jet LS ON;
  pending source campaign unchanged. No phones/cloud/Git publication/TestFlight.

## 2026-10-24: Private170 AS live-schema repair passes real decoder; picker stays open

- AS changed its live football row to an undated reviewed LIVE shape and public
  ID without the old football prefix. Join only that shape by literal public ID
  to fresh fixed-route publisher metadata with explicit sport/full UTC/teams.
  Preserve original dated parser, shared date/squad/conflict vetoes, cancellation/
  byte/row/time bounds and existing media TLS/public-IP/redirect/header contract.
- Twelve focused regressions;48 Catalyst passes/one physical-only skip. Exact
  Villa–City24Oct11:30UTC physical AS test passes878 actual720p frames/92.080s
  progression/90s hold. Contemporaneous native programme is TNT AVL1–0MCI32:13.
  Retained relay32completed/zero failed/four evicted; no total-request claim.
- Normal signed Release170 restored, installed/read back and launched; frozen
  source comparisons,45 protected hashes/four private FPL values and all prior
  source choices pass. AS remains OFF: mirrored taps did not activate Settings,
  even after screen-share reconnect. Decoder acceptance does not establish normal
  picker, controls, audible output or PiP. No confirmed app-hang diagnosis.
- Additional cricket remains pending compatible dated programme/delivery proof.
  No invented fixture, security exception, source injection or broad failure
  claim. FPL/multi-stream/phones/cloud/Git publication/spending/TestFlight remain
  unchanged. Preserve release170/audit and clean only owned temporary output.

## 2026-10-23: Quiet-window source availability stays pending, not permanently rejected

- Owner clarified that scarce late-night football coverage is not grounds to
  eliminate a source. Empty catalogs, upcoming fixtures and zero advertised
  servers remain pending live-window evidence. Keep source-specific transport,
  identity or programme limits separate from provider-wide availability claims.
- Fresh AS/Tigre samples first decoded as two black six-second segments, then
  one later720p segment visibly showed the correct TIG–ATU programme. This
  establishes changing output, not the cause of the black intervals or a native
  playback pass. A generic reachable Three channel does not corroborate carriage
  of the24Oct second NZ–India game; reviewed cricket candidates remain pending.
- Pin the opt-in Plavio physical helper to the independently verified
 24Oct00:15UTC Tigre fixture, real adapter and existing date/admission guards;
  require90s hold/80s decoded progress/140s maximum. CNC behavior and production
  matcher/player/security/defaults stay unchanged. No invented native fixture.
- The Jet physical test skipped at stream resolution after1.115s:0pass/1skip/
  0failure, no relay or frames. A fresh dated catalog entry remained, but its
  descriptor now supplied only unavailable copy and a non-media placeholder.
  Successful Xcode execution is not a successful playback test. AS qualification
  and normal-picker acceptance remain open; no source was removed or promoted.
- Normal signed Release169 restored and launched; AS OFF/all five original
  source choices, four private FPL values and45 protected file hashes preserved.
  FPL, multi-stream, phone, cloud, Git publication, spending and TestFlight remain
  unchanged. Keep the dated audit receipts; remove only owned temporary output.

## 2026-10-23: Private169 additional NHL source qualifies; failed deliveries stay excluded

- Research actual new deliveries, not renamed CS or generic-channel fixture
  guesses. Add a separate default-OFF LS/CNC lane to existing exact match source
  lists, with dated metadata, exact sport/teams/squad and conflict vetoes. Current
  admission is NHL/hockey and the reviewed HTTPS443 host7 route/public headers
  only. No arbitrary add-on, auth, exceptional port or new relay trust grant.
- A real partial-playlist defect forwarded Range0–1 then rewrote two bytes.
  Require full200 playlists and suppress representation preconditions only for
  known m3u8 requests; preserve segment ranges and reject partial MIME playlists.
  Exact reviewed LS single sessions get an immutable30s startup budget; default
 20s, handoff/pair, buffer/stall/recovery/intent rules stay unchanged.
- Reject the sampled NBA/host4 lane: early20s video decoding was followed by a
  failed90s hold and normal-app stall. Synthetic relay capacity is12.23MiB/s,
  which excludes only that setup's basic throughput shortage, not provider fault.
- Fresh gate:285 pass/two intended physical-only skips, zero failures;32
  membership tests. NHL native90s hold passes877 actual720p frames/91.966s
  progress. Normal Release169 adds LS1 beside six sources, decodes3346ms, shows
  correct Blackhawks–Canadiens programme and264.984s attempt without failure or
  failover, including fullscreen/return/Pause/Resume. No PiP/audio/full-league claim.
- Signed/source/install/readback/launch169 pass.45 protected hashes/four private
  FPL values and existing source choices unchanged; LS privatelyON Jet/defaultOFF,
  AS OFF. No phone/FPL/multistream/cloud/Git publication/spending/TestFlight.
  See release169 and dated new-sources audit; remove only owned temporary output.

## 2026-10-23: Private168 additional-source adapter held pending video qualification

- Research actual additional deliveries, not renamed CS, an assumed installed
  Nuvio sports add-on, BYO-playlist tools or non-media placeholders. Plavio has
  one reviewed dated-football delivery contract; its sfly/Leaf/Highfly ancestry
  does not establish independent upstream resilience.
- Wire a separate default-OFF AS1–AS6 lane into existing exact match sources,
  finite redacted attribution and the existing discovery budget. Extract pure
  matching without changing CS schema/transport/admission. Preserve headerless
  guarded-relay intent through model copies/persistence. No new trust exception.
- Final local gate:238 passed, one intentional physical-only skip, zero failed;
  32 membership tests, version/membership/signature/source/install/readback168
  pass.45 protected FPL/multistream hashes and device FPL values remain unchanged.
- Actual Jet video acceptance FAILS: ready/playing item and media200, but zero
  decoded frames/black visible AVPlayerLayer after40s. Corrected test watchdog,
  actor isolation and Apple display-clock sampling improve evidence, not proof.
  The exact fixture then returns no admitted HLS, so no codec diagnosis is made.
  Keep AS OFF and the new-source milestone OPEN; no source-picker/fullscreen/PiP
  success is inherited from old playback tests. Restore normal Release168 on Jet.
- No phone/FPL/multistream testing, shared default activation, cloud/Git
  publication, spending or TestFlight. Clean only the owned temporary build gate.

## 2026-10-23: Private167 exact HTTPS CS route; retain blocked HTTP delivery

- Owner explicitly approved only the verified advertised HTTPS CS route and
  Jet iPad testing, not TestFlight. Admit the exact reviewed manifest/sktech/
  dai-fancode.pages.dev HTTPS443 HLS-path/public-header contract. Preserve the
  existing guarded native relay, TLS/public-address/redirect/header constraints,
  opaque CS labels and source opt-in. No player/proxy-policy or port expansion.
- Reproduce and close the headerless API-wrapper hole: inspect wrapped targets
  across case/encoded API paths and duplicate/case-insensitive URL parameters.
  HTTP2122 remains rejected; retain only the existing bound HTTPS8443 exception.
- 144 fresh focused tests pass, zero failed/skipped;32 membership tests and final
  signed/source/install/readback167 pass.45 protected FPL/multistream hashes
  unchanged. Release167 records the frozen tuple and intermediate red test.
- Physical CS decoding remains open: Jet screen is visible but remote touch/Home
  failed after reconnect/relaunch. Do not mislabel this as source failure or a
  playback pass. No phone/FPL/multistream/shared release/cloud publication.

## 2026-10-23: Private166 official-fixture CS checks; new delivery trust remains a gate

- Owner approved independent CS checks from official fixtures and stopped
  repeated accepted playback testing. Add a manual Details action, not fake Watch
  availability. Require existing CS opt-in, fresh verified canonical two-team
  metadata, current exact identity/status/timing, foreground ownership and
  pre/post lookup revalidation. Only descriptor absence is offer-only; a refresh
  adding a primary descriptor does not discard a valid pending CS result.
- Merge independent title/cast squad evidence and quarantine conflicting IDs/
  effective targets. A physical regression exposed the native competition prefix
  in cricket request titles; use the exactly agreeing official participant pair,
  without relaxing ambiguous remote or adversarial request-title rejection.
- Physical R2 hits the7s stream timeout; the same endpoint returns200/3 entries
  at8024ms on Mac. Give only CS stream lists11s request/12s transport, preserving
  manifest/catalog7s/9s, outer18s, no retries and existing admission/security.
- Final166r3:98 focused tests pass; signed/source/Jet install/readback/launch,
  app+extension166 and45 protected file hashes pass. Source tuple, intermediate
  failures, exact tests and physical receipts are in release166. Prior165 full
  suite/PiP passes remain dated evidence, not new166 every-source qualification.
- R3 reaches3 rows in7169ms but rejects all deliveries: donation, new HTTPS HLS
  host dai-fancode.pages.dev and wrapped HTTP-IP:2122. Bounded HTTPS master200/
  public DNS/no redirect/no segments is not playback. Ask owner before narrowly
  admitting the new HTTPS route; HTTP2122 stays blocked. CS decoding remains
  open. Do not misreport this as fixture absence or an upstream lookup outage.
- FPL, multistream, phones, shared/cloud activation, Git publication and TestFlight
  are unchanged. Preserve owner preferences; clean owned temporary output only.

## 2026-10-23: Private165 source selection, CS, recovery and usability repairs

- Follow the owner's order and Jet-only gate. Keep FPL, multistream work/testing,
  phones, shared121, backend/source activation and TestFlight unchanged. Full
  pre-existing unit suites are not physical FPL/Watch Two acceptance.
- Reserve bounded discovery result slots for independent pending families; hold
  validated siblings unpublished, release reservations on exhausted lanes, never
  evict published choices or flush after owning cancellation/grace expiry. Keep
  existing result/concurrency/time limits. Recheck shared-embed redirect scope and
  destination cookies at each hop. Explicitly cancel a refused redirect body so
  admission refusal cannot degrade into timeout. Do not expand source trust.
- Isolate malformed CS rows within100 while retaining valid siblings; top-level
  corruption stays fatal. Manifest generations fence stale publication. Preserve
  advertised preferred-catalog failure when optional fallback finds nothing; do
  not conflate it with ordinary empty discovery or suppress conflict/cancellation.
- Capture a weak exact native PiP background observation lease, consume it once
  on active to rearm existing watchdog observation. No Play/reload/seek/new retry.
  Pause/replacement/non-single routes do not inherit it. Home/Matchday exact
  retained reopen preserves source/attempt/Pause after current identity checks.
- Search adds reviewed aliases including official FC suffixes without changing
  stream matching; women/youth/sport/league fences remain. Adaptive loading keeps
  phase text readable without duplicate single-player controls; assistive-tech
  control visibility is policy-tested. Apple UI guidance preserves badges/artwork.
- Final frozen r5 passes1611/two existing optional skips/zero failures,32+13
  Python and54 Node tests, native membership/version/generic/signed/signature/
  source/Jet install-readback165/launch. All42 FPL and3 multistream hashes match.
  Source tuple and initial corrected test/redirect failures are in release165.
- Final Jet passes actual source change, native fullscreen, Pause>1min/Play,
  paused Home Watch reopen, >60s Springboard PiP, system Pause>1min/Play/Restore
  and inline. Same source/attempt/presentation receipts corroborate Restore.
  CS metadata is currently healthy, not decoded-media proof. Existing admission
  excludes official source-free rows; preserve CS as extra sources rather than
  fabricate primary descriptors or infer programmes from Willow/Fox. Current CS
  decoding, audible output, lock/unlock and physical assistive-tech gates remain
  open. Do not inherit old163/164 causes or claim full TestFlight readiness.

## 2026-10-19: Private164 single-stream recovery and truthful CS evidence

- Scope remains single-stream on Jet only; FPL, multistream features/testing,
  phones, shared121, source trust and remote publication/deployment are untouched.
- Empty CS catalogs expire in15s rather than120; populated TTL stays120. Exact
  generations prevent a late actor response overwriting newer data; rollback
  invalidates cache. Absent fixture, raw-empty streams and rejected delivery now
  have distinct finite outcomes/counts. No extra polling/retry or invented source.
- Background fatal native item events record the exact incident immediately,
  with no background transport mutation. Foreground consumes once using existing
  bounded recovery, respecting Pause and current ownership. Verified ready-surface
  progress beyond the latest fatal boundary retires even a consumed paused
  incident; an old failure cannot cut recovered video or hide the next failure.
  Model background state also fences detached fullscreen PiP callbacks.
- Initial native observer exit reasons and first resumed displayed progress gain
  bounded local evidence without new timing/transport behavior or fake latency.
  Initial startup health/latency is once per single source/attempt; repeated Web
  owner starts still complete recovery without recounting. Native adoption is a
  separate once-only receipt, never a still-Web preparation callback. Existing
  multistream bookkeeping remains. Finite native presentation edges are capped
  once per lease in the existing local store, not an uploaded/full event timeline.
- Final r4:1569 passed/two optional skips/zero failures, tooling/generic/signed/
  strict signature/source compare/Jet install-readback164/launch pass.42 FPL and
  three multistream-specific hashes unchanged. Initial test compilation typo was
  corrected before the clean gate. See release164 for immutable source tuple.
- CS is enabled, with exact current catalog identity. Jet163/164 stream-list
  timeouts and a separate Mac9s timeout corroborate upstream resolution slowdown,
  not a matching defect, global outage or provider-only HLS cause. Regular Web
  video, explicit Pause>1min/Play and source actions have current visual evidence;
  startup failures/buffering remain. No available CS/native candidate means native
  fullscreen/background PiP/Restore/inline/audible gates remain OPEN. Do not claim
  full single-player completion or TestFlight readiness. Temporary gate is cleaned.

## 2026-10-19: Single-player reliability first; private163 fullscreen ownership repair

- Owner explicitly puts stable single-stream playback and reliable streams ahead
  of Watch Two. Defer multistream implementation and physical checks until last;
  running pre-existing pair regressions in the full unit suite does not qualify it.
  FPL/phones/shared121/backend/Git publication stay unchanged; no TestFlight.
-161–162 implement eight controlled playback-lab scenarios/27 actual selectors,
  ephemeral declared/observed source contracts, preparation factories and the
  same cookie-scoped delivery for single native validation/adoption. Each relay
  keeps32 bounded memory-only request receipts with exact cancellation/deadline
  ownership and atomic scalar summaries, never raw URLs/headers/cookies/bodies.
  Causal correlation/old error age must not be presented as terminal-cause proof.
  Source-health queries reuse exact-byte cached decoding on the existing queue;
  Home child signposts support future measurements, not a claimed FPS improvement.
-162 physical failures expose a real stale-fullscreen lease: same AVPlayer item
  replacement can leave AVKit attached while callback guards reject its attempt.
 163 permanently revokes and synchronously detaches the exact borrowed controller
  before admitted load/attempt/player replacement or cleanup. Ordinary retained-
  PiP Done remains separate; no new Play/Pause/seek/reload/audio/trust operation.
  Six real-controller regressions plus full1535-pass/two-skip/zero-fail gate pass.
  Initial163 second-lease fixture readiness error is corrected before final r2;
  production behavior/assertions are not weakened to pass. Tooling/native/signing/
  source/install/readback163 pass; all42 FPL hashes equal the task baseline.
-163 CS1 exact fixture/decoded recovery, Apple fullscreen and floating decoded PiP
  have bounded visual evidence. CS1 twice fails CoreMedia-12312/segment URI changed;
  CS2 later records stalled; CS3 preparation timeout then decoded recovery follows.
  Later CS2 evidence supersedes an early snapshot without its failure, but does
  not prove why its floating window vanished. >60s Home PiP/Restore/inline return
  and current audible acceptance remain open. No speculative background patch or
  provider-only conclusion. Source errors do not establish uninterrupted playback.
- REA native providers are unconfigured, physical XCTest snapshot waits prevent
  useful metric sampling and xctrace attach yields no usable comparison. No native
  REA or physical speed proof. Additional-source shortlist remains research only.
  See releases162/163 for provenance, exact attempts and caveats. Temporary gate
  uses one reused directory, then owned outputs/runner/awake process are cleaned.

## 2026-10-16: Private160 bounds native resume and records the unfinished conversion gate

- Owner accepted a brief coordinated both-native restart for deliberate Watch Two
  audio selection.157 prepares both captured candidates paused/disconnected,
  awaits both exact Web teardown ACKs before either Play, and rechecks owner,
  source/request/intent epoch/scene/generation. Preflight failure preserves current
  viewing; post-retirement failure cannot revive only one Web pane. Pause→Play
  invalidates stale work. Do not force Play, bypass unknown Pause or mix globally.
-158 validates the actual prepared cookie-scoped relay without broadening trust.
 159 records candidate-local bounded item/error-log/relay details. On159, readiness
  failure has URL-1102/CoreMedia-12660 and relay HTTP403 aged86ms; both original
  Web pictures advance. Safe refusal passes, successful conversion does not.
-160 repairs a real AVKit recovery gap: legitimate foreground Play while waiting
  rearms the existing watchdog/eight-second resume validation and recovering state,
  without extra Play/seek/reload. Pause cancels it; exact presentation/item/source
  guards and background policy remain. Four regressions include deadline execution.
  First160 test gate hung on an unrelated delay; corrected test-only r2 passes.
- Frozen160r2 passes1489 units/two optional skips/zero failures,32 tooling,
  generic/signed native, strict signature, source compare, Jet install/readback/
  launch. All42 FPL hashes equal159. Receipt commit
  d71ef5c2a6e8626264ba8f75ea37ce15756460e8, source
  9798e87abbf332ecb350a30395d25b6857983444f6c30b8529a6c396d5ed61ad.
- Current160 Detroit CS1 has bounded fullscreen Pause/Play, retained-Done PiP
  Pause/Play/actual Restore, >60s Home PiP/background Play/Restore and inline return
  visual passes. Native pair selected-audio UI/Swap/Pause preservation/Keep-right
  pass; no audible or exact-object claim. Orlando later stalls with error-log
  CoreMedia-12312/discontinuity change, earlier404 age101s; CS2 then URI-change
  failure, same-source retry recovers. Tags and identical-URL routes are stable in
  source review; no demonstrated relay cause. Do not hide consistency errors by
  modifying tags, widening aliases or weakening source guards.
- Positive real Web/Web→both-native conversion and reliable pair media remain
  open. Native/native success and safe403 refusal are not substitutes. See
  releases/Fotty-2.0.1-160.md for exact outcomes/receipts. Phones/FPL/shared121,
  sports sync OFF, backend and Git remotes unchanged; no TestFlight.

## 2026-10-16: Private156 qualifies bounded native PiP, not Watch Two audio

- Continued approved Jet-only repairs/install/tests without repeat routine
  approval. Phones, FPL, shared121 and backend unchanged; no TestFlight or remote
  publication.156 passes1458 units/two optional skips/zero failures, tooling/
  native/signature/source/install/readback; all42 FPL hashes unchanged. Final r2
  receipt source51cf3fe7c45256dbd829b5f97daf9c9cc21531cac18902a48f69742aba0ce74f,
  local recovery commit75a0b08ed5bff7620630fe67435bc8f2884c21b9;1108 inputs compare.
- 155 replaces passive native probing with cached candidates and explicit single
  Use Native Player; exact Web suspension precedes candidate Play, old-Web teardown
  precedes selected native audio. Compatible-original-route context also fences
  source/retry/fallback. Failed native-retirement Retry renews its ACK barrier.
  PiP restore follows legitimate same-window presentation chains without reload.
- 156 awaits exact decoded-owner/document managed-mute readback, not parent JS
  evaluation. Startup requests preserve original deadlines. Aggregate old-attempt
  tickets survive replacement/cleanup/re-enable; new replies cannot clear old
  owners. Disabled return-to-single remains managed until coordinator release.
  First156 run caught an obsolete assertion; corrected before final r2 green gate.
- Physical156 Golf50283DCC+DartsC899F2C0 both advance, but Darts Audio pauses Golf
 18:30:49.006UTC despite prior Play intent and mute ACK; candidate_count0. Confirmed
  failure, not merely untested. Independent source review finds no justified small
  focus patch. WebKit process arbitration is possible, not confirmed Jet internals.
  Never force Play, ignore unknown Pause, mix globally or weaken source safety.
-156 single explicit native adoption18:45:18.542, exact Web retirement18:45:18.765
  and activation18:45:18.857 pass causal order. Actual fullscreen Pause/Play,
  retained-Done PiP Pause/Play/actual Restore, >60s Home PiP and paused Restore
  pass visual checks. Later Play/Close coincides with failed_to_play_to_end,
  CoreMedia-12312 at18:50:16.188; Web fallback recovers on retry. Cause unknown;
  no uninterrupted inline-return or provider-only claim.155 inline pass is dated
  historical evidence. No new crash report, exact-object or audible proof.
- Stronger both-native Watch Two needs an atomic pair transition, not two
  single transfers: validate both paused/disconnected candidates, retire both Web
  owners with exact ACKs, then start native pair preserving intent/focus. Brief
  restart and native-candidate coverage gaps are material behavior decisions;
  not implemented/qualified. Current playback gate remains incomplete.
- Stopped media/PiP, restored All sports/empty test query/history/Light/landscape;
  interests unchanged, sports sync false. Removed only owned reused1.1GB gate;
 18GiB free. Keyboard capture off, Device Hub closed, owned awake process absent.
  Source recovery receipts/installed156 retained. See release156 for evidence.

## 2026-10-16: Private154 isolates native audio but mixed playback remains blocked

- Jet-only playback continuation; phones/FPL/shared121 and backend untouched.
  Frozen154 passes1392 units/two optional skips/zero failures, tooling/native/
  signature/source/install/readback; all42 FPL hashes unchanged. Receipt source
  071dd5344dd58dd2489b8457920d02b0b423e84283cf62996a3b2a5565444b83,
  commit bf7f91a9675bcd0516d2652e0de7b8becf52f7a6;1107 inputs compare.
- 149 adds bounded local causal ordering;150 separates native dismissal from
  retained-PiP control admission with locked epoch tickets.150's actual watchdog
  report confirms a quality-lock/Defaults/main-observer deadlock, not a tool-only
  freeze.152 drains Defaults outside diagnostic locks with revisioned overlays;
  six reentrancy/lock regressions pass. No new telemetry uploader.
- 151 defers adopted audio until exact Web retirement.153 serializes public iOS27
  per-player disconnection ACKs;154 removes even candidate configuration. Preserve
  source/request/item/intent/focus/scene fences and unsupported-runtime Web fallback.
  Apple audio disconnection is not a promise of concurrent Web/native video.
- 154 Golf native/Tennis Web still fails: sibling Pause accompanies silent native
  adoption and later actual native activation. App remains responsive. Explicit
  Tennis Play restores two advancing panes. Do not ignore unknown Pause, force
  replay or add global mixing. Explicit transfer/compatible-pair policy or a
  coordinated both-native transition is a material next product decision.
- Current154 Golf native fullscreen/Pause/Play, >2min advancing Home PiP, actual
  system Restore preserving Pause, subsequent Play and inline-after-Close advance
  pass visual checks. Retained-Done PiP Pause/Restore remains unqualified after a
  separate repeat. No exact-item, audible or all-native-pair claim. Fresh crash
  listing contains150 and10Oct only. See release154 for causal times and limits.
- Source review also finds failed native-retirement Retry reawaits the same failed
  barrier. Focused renewal/regression remains open; not the observed mixed cause.
  No speculative restore hierarchy changes without delegate/presenter evidence.
- Stopped test playback/PiP, restored All sports/empty test query/history and
  original Light/landscape; sync OFF/interests unchanged.154 normal relaunch and
  readback pass. Removed the owned1.1GB reused gate;18GiB free. Keyboard capture
  OFF, Device Hub closed, owned awake process/assertions absent. Valid source
  recovery receipts remain; permanent sleep/security and unrelated data untouched.

## 2026-10-16: Core experience in private Jet 148 with mixed playback gate open

- Four approved DAZN/ESPN/Apple-inspired core batches are implemented: truthful
  playback/recovery, whole-sport interests and explicit Home/Matchday scope,
  per-pane Watch Two/source actions, and Search/details/save. FPL and phones are
  unchanged; no TestFlight, remote publication or backend deployment.
- Native inspection caught and repaired source availability pushing imminent
  followed cricket below tomorrow's football, and Until midnight truncation in
  the iPad Time window sidebar. Regressions preserve live/source prominence,
  broad Home ordering and anchored window semantics. Native 148 confirms both.
- Frozen-source Catalyst 1346 pass/two optional skips/zero failures, 32 tooling
  tests and generic native Release gate pass. Signed 2.0.1(148) installs/readbacks
  on Jet Air4/27.0.1. All42 FPL hashes equal the starting state. Receipt source
  1480346810f33003203ae2a8abbef2b0fd007d2de704f546c9a30be22fc25ced,
  local recovery commit6eb220d74fe15bc0051ae4eab1c464413aa6d764; all1106 inputs
  compare before build/install and acceptance notes. Production stays frozen.
- Actual Home/interests, Matchday window/recovery, Search/recent clear,
  Details/Save/Remove, source selection, per-pane controls and right-pane Keep
  pass bounded normal-touch checks. Real ONE native AVKit fullscreen/Apple Play
  advances video. Native component goldens were visually reviewed, not treated
  as a device journey or marketing preview.
- Mixed Web Darts/native ONE fails: adding/resuming one pauses its sibling.
  Platform media arbitration is supported by WebKit source, not proven exact
  causation. No global mixing, forced resume, source weakening or unknown-pause
  bypass was applied. Need bounded handoff/audio/pause evidence and focused
  repair. Current native extraction already exists. All-native pair and actual
  PiP Restore/fullscreen Close/inline journey remain open; 146 is historical.
- Physical XCTest executed no methods because Touch ID UI automation approval
  was unavailable. Cancelled normally; no authentication bypass. Device Hub
  manual evidence is not exact-item, audible or continuous-frame proof. See
  release148 for limitations, settings restoration and owned-output cleanup.

## 2026-10-13: Native fullscreen restored in signed146; Jet-only qualification

- Owner approved native fullscreen without stream restart, preserving the new
  retained experience, Jet testing only, phones/FPL alone and no TestFlight.
  Custom Focus was not the expected native media experience. Actual AVKit
  fullscreen is now separate from Focus/Companion, not a broad design rollback.
- NativeFullscreenSession borrows exact player/item/source/attempt. The actual
  AVPlayerViewController is presented from the retained marker's own scene;
  entry/Close adds no URL/load/seek/autoplay. Inline rendering and PiP detach,
  not the scene-owned pane. Current-owner/deferred-update guards preserve the
  new lease and explicit paused intent; model-owned rate changes are excluded
  from system user commands. Failed PiP restore does not clear closing state.
- Shared test measurement identity survives temporary inline nil/detachment.
  This repairs an actual harness token reset, not proof that the stream restarted.
  Eighteen added regressions; complete Catalyst1300 pass/two optional skips,
  zero failures. Native compile/signature/source/install/readback pass.
- Jet real CS6 fullscreen controls test passes: two presentations/Close returns,
  Apple Pause/Play, deliberate paused re-entry, repeated transport, advancing
  inline and Stop. Same player/item/attempt throughout. Actual landscape Apple
  controls and companion return inspected; no new phone/portrait/audio proof.
- Earlier8s Resume check captured rate1/waiting. Bounded30s progress passes with
  the existing12s buffer target unchanged; no proven app pause or provider-only
  cause. CS6 PiP stalls before request, with buffering already present inline;
  do not claim a request/pass or causation by fullscreen.
- CS1 PiP survives60s visible Home with same owner and65.597s media advance.
  Overall Restore tests remain failed/unqualified: actual OS button is not
  exposed to XCTest. Both Restore success paths now require PiP disappearance;
  an already-present fullscreen marker is not proof. No app-layer substitute.
  Later strict CS1 fixture repeat and separate available-broadcast native setup
  skip; finished fixtures and WebKit are not native/CS acceptance substitutes.
- Immutable pre-build146 receipt: backups/release-source/2.0.1-146-native-fullscreen,
  source69f7c82c1525f97a334528b80872e2acf7217752de638a18b87955154980f523,
  commit08a9000c045bd29844ee094411ee51c346bd2b92. All1105 inputs compared before
  install. Final review: only UI harness changed after capture; production still
  matches. All42 FPL source hashes unchanged. Shared121/phones125 stay unchanged.
- See release146 for exact acceptance limits. Sync/widget/Watch Two gates remain
  separate. Owned build/results/screenshots/UI runner and keepawake are cleaned;
  installed Fotty/source-recovery receipts are retained. No release/publication.

## 2026-10-13: Signed143 on Jet; incomplete sync/playback/widget acceptance

- Approved scope remains Jet iPad only, sports sync and playback/widget checks;
  leave phones/FPL alone, no TestFlight, backend or Git publication. Owner's
  fullscreen objection pauses further player presentation changes. The retained
  custom Focus view is not Apple's system fullscreen. Restoring true fullscreen
  with the same native player is a proposal, not an implemented fix. Do not
  claim an AVPlayerViewController was removed: current and inspected older
  renderers use AVPlayerLayer/custom controls; provider fullscreen is distinct.
- Sync preserves v1 records/journals/receipts and reads legacy cloud slots;
  v2 writes are disjoint per installation-origin and intent. A device-only,
  non-synchronizable Keychain identity plus local marker detects restored/copied
  installations. Account guards, consent and quota preflight remain intact.
  Synchronize attaches/queues; neither notification nor queue proves delivery.
- Confirmed stale projection echo is repaired: passive applied-snapshot writes
  compare their expected receipt after cloud reconciliation and request reapply
  rather than overwrite a newly arrived record. Intentional user edits retain
  their separate rebasing behavior.26 sync/14 bridge tests cover late data,
  account/off behavior, restore, quotas, and save/remove races.
- Immutable installed source: backups/release-source/2.0.1-143-jet-sync-playback,
  commit b1cb1e75c37f5ae8eaecfc9d0c354b692e983bba,
  sourceSHA256 c651a698db523346cca85f76545121259e19ee90b083e9b1eb8533aea2c4b0d8.
 1102 source files compared before install; strict app/extension signature,
  approved App Group/KVS entitlements and actual2.0.1(143) readback pass. All42
  FPL source hashes unchanged. Sequential Catalyst qualification:1282 passed,
  two optional skips, zero failures; native Release build-for-testing passed.
- Actual Jet sync-OFF check passes; real temporary first opt-in fails safely
  after30.610s, returning OFF without a queued state. No synthetic notification,
  account reset or false cross-device claim. Writer exists; account marker absent.
  Later source-only failure-stage diagnostics distinguish writer/account/cloud/
  account-change failures and expose failed opt-in status; syntax parsed only.
  These diagnostics are NOT in installed143 and require rebuild/qualification.
- Exact real Arsenal FC vs Lille OSC CS5 decodes. Earlier short-name setup skips
  are not passes. Correct-name physical PiP and rotation tests fail: before PiP
  interaction, the source attempt/item is replaced and becomes unready, so the
  PiP button no longer exists; no PiP request occurred. Requalify actual source/
  item/attempt and investigate retry before testing. Do not tap old coordinates.
  Rotation's first window is0x0 auxiliary AVKit; the actual820x1180 main window
  has an accessible44x44 exit. Correct this confirmed harness defect first;
  do not label it a proven production rotation failure. Neither harness fix is
  implemented yet. CS6 same-item PiP pause and strict two-native-picture gates
  remain open; no new Watch Two pass.
- Widget Home inspection passes, no widget or saved match was added. Population,
  native tap, real1801s expiry and ownership cleanup remain unqualified. Latest
  source-only harness tightens row-specific assertions, snapshot epoch, removal
  ownership and bounded one-read-per-icon geometry; syntax parsed, not compiled.
  Keep actual medium/large sports-only widget/new-empty-page safety, no FPL,
  reminders, clock changes or substituted deep links to manufacture acceptance.
- Temporary Xcode/results/screenshots (1.3GB) and owned UI runner were removed;
  the actual Fotty app remains installed. Bounded keepawake stopped. Do not treat143 as
  TestFlight-ready or discard the installed receipt because working source has
  subsequent unbuilt diagnostics/harness edits.

## 2026-10-13: Signed142 on Jet; bounded native acceptance and honest open gates

- Owner signed into Xcode; refreshed profiles activate the approved sports KVS
  and App Group. Strict signed app/extension and exact Jet2.0.1(142) readback
  pass. Shared storage has only the sports saved-plan snapshot; actual sync
  remains off. Owner phones125/shared121, FPL and backend remain unchanged.
- Focused device fixes preserve the permanently retained pane tree: explicit
  accessibility containment, modal foreground/lookup Cancel, disabled covered
  background, and warm sports-plan/Matchday minimization before destination.
  Small widgets use one URL; larger families keep Links; FPL route/widget unchanged.
- Corrected harness semantics, not production Search: whole committed queries,
  normal refocus after Clear; raw XCTest existence is not VoiceOver focus proof.
  Real touch isolation passes; assistive traversal is still a separate gate.
- Final seven physical tests: five pass, widget test timeout fails before native
  gallery, Watch Two skips with exact source-retry/fallback evidence. Earlier
  corrected source/control runs remain dated evidence, not two decoded/audible
  panels. Final retained Web pause/Focus/warm-link/Stop passes, no native identity.
  No unsupported idle controls or inflated timeout were used to force green.
-142 native PiP setup lacks a ready hook;141 CS6 PiP pause remains unresolved.
  Cross-device cloud/Handoff, phone visuals, real VoiceOver, populated widget
  timeline/link/expiry and two decoded/audible pictures are not qualified.
- Final source recovery: `2.0.1-142-jet-complete`, commit62a2ce5/source4e733424;
  1101 files compared before install.32 inventory regressions and all42 baseline
  FPL source hashes still pass. Exact gates/provenance: release142. No Git
  publication/backend/TestFlight; owned test products/runner are cleaned.

## 2026-10-12: Approved retained viewing experience and sports-only continuity

- Owner approved the full iPhone/iPad concept, private Jet testing, unchanged
  FPL and no TestFlight. Sports-only iCloud/widget capabilities are explicitly
  approved; sync remains off until opt-in. No backend, Git or shared release.
- One scene coordinator owns persistent media panes and prepares destinations.
  Compact/full/Focus/Watch Two change presentation, not item/source/attempt.
  Scene-specific teardown, per-owner remote fencing, exclusive audio and actual
  PiP claim reconciliation preserve paused intent and avoid orphaned transport.
  Typed terminal/conflict facts are rechecked before new viewing admission.
- Matchday now offers an anchored personal Tonight window without duplicating
  the catalog or collector. Home's quiet football backdrop reuses bundled art.
  Real badges/sports equipment and native tab-accessory navigation remain.
  Cricket companion has schedule/status only; no invented scores/overs/stats.
- Explicit Handoff carries only an expiring match identity and fresh receiving
  confirmation. KVS uses bounded sports intents, canonical wire values, durable
  verified applied receipts and pending/error separation; failures cannot echo
  old local values or revive tombstones. FPL, source credentials/URLs, history
  and device reminder consent are excluded. KVS is not an encrypted vault/ACK.
- Sports widget uses a signed App Group and expiring saved-plan snapshots; its
  links open Matchday without autoplay. Unsupported football live metrics are
  omitted rather than renewed from a global feed timestamp. FPL widget unchanged.
- Final full Catalyst suite passes1264/two optional skips/zero failures. Ten
  component PNGs were explicitly inspected: only five approved Home backdrops
  change; sources/controls/badges are byte-identical. Non-recording visual gate
  passes. All42 FPL Swift file hashes match the turn's starting state.
- New signing is blocked: cached profiles lack iCloud/App Groups and Xcode has
  no account. Accounts screen opened for owner sign-in; Jet stays locked and141
  is not replaced. No physical/cross-device/widget acceptance is claimed. The
  separate141 CS6 PiP pause remains unresolved. Exact status: release142.
- Current-source unsigned native app/extension and temporary UI-only Release
  test compilation pass. The temporary scheme is removed; owned outputs and
  keep-awake are cleaned after recording the staged recovery receipt.

## 2026-10-11: Resumed141 CS playback and PiP qualification on Jet

- Owner made Jet available; scope remains single-player CS/PiP, no TestFlight.
  Rebuild uses saved141 source unchanged; signature/source/readback pass.
- Exact CS5 maps to streamedpk, not a fallback. Native/source controls,60s
  visible Home PiP, same-item/attempt, ordinary Stop/inline/Close pass;51.782s
  round-trip advance. Separate read-only observations show changing PiP frames
  before reactivation. Passive buffering persists; muted testing is not audio.
- CS1/DaddyLive short native/control check passes. CS6/timstreams starts and
  shows changing background frames, but fails >30s advance and is paused on
  return with the same item/attempt. No fatal/retry/fallback establishes cause.
  Fresh playlist lacksENDLIST/VOD; its20.020s window is not programme length.
- Home/Search retries skip after the exact real Watch row disappears; never
  count those as passes or erase the failed CS6 result. Retain the remaining
  qualification gate instead of guessing a lifecycle or provider repair.
  See release141 for finite attribution/provenance; no production edits.

## 2026-10-11: Score identity, CS wrapper and fair-cap repairs; owner testing stop

- Approved score/remaining-CS/PiP scope only. Full nonblank football identity
  replaces display-code matching in score/freshness joins; squad/date/opponent
  safeguards remain. Five official-mapper/service/Home regressions pass.
- Confirmed native CS segment-URI rotation preserves the entire encoded query
  but changes among reviewed outer Worker hosts. Runtime profiles retain the
  first admitted immutable URL/headers, including the verified exact TikTok
  image host; no signatures, media bytes or destination protections change.
- Six-choice CS truncation could hide later upstreams behind ten initial
  variants.141 admits/deduplicates100 max, reserves groups, fills slots and
  preserves selected order/profiles. Four regressions and independent reviewGO.
- Frozen/signed141 installs Jet;1172 units/two optional skips pass. Initial
  synthetic NSCache/visual failure passes unchanged rerun; cause unresolved.
-140 CS6 PiP passes full60s Home, same item/attempt, Stop/inline/Close, but its
  actual source key proves DaddyLive, not the repaired streamedpk format.
 140 native Home shows the current official Liverpool–City0–0 score.
- Owner stops141 exact-CS5 PiP to watch the game. Host/runner stopped; leave
  Jet alone. No partial141 test counted; opaque-key attributed repaired-format
  PiP/controls remain open. Source receipts retained, owned temporary data
  cleaned. No Watch Two/UI redesign/phone/backend/Git/TestFlight actions.

## 2026-10-11: Bounded remaining-CS qualification and score identity diagnosis

- Owner scope: remaining CS and Jet iPad testing, plus Palace–Forest explanation.
  No Watch Two, redesign, score production edit, phone, TestFlight or publication.
- Real CS1–CS6 choices/control/native gates distinguish each requested family
  from its explicit failed-row/fallback. Short CS2–CS6 decoded passes do not
  establish continuity: fresh delivery404, no-ready-layer startup failures and
  CoreMedia fatal/retry receipts remain real open acceptance failures. Exact
  underlying fatal cause is unknown; no header/cache/lifecycle defect is proven.
- CS2 retains same native identity and >30s time advance across60s visible Home
  and return. Stop/inline gate is blocked by remote PiP AX hittability. Fix only
  the test helper's ordinary drag prerequisites, retaining exact geometry,
  actual movement/non-overlap/Stop hittability and all native assertions. Signed
  compilation/source/signature pass; fresh CS1/CS2 deliveries fail startup, so
  the corrected drag is not runtime-qualified. No full CS PiP acceptance claim.
- Confirmed score code defect: official CRY/NFO display labels are incorrectly
  used for service identity/freshness joins with full-name catalog/observations.
  Feed had2–1 when checked; exact failed device poll was not retained. Recommend
  full-name identity plus mapper/service/Home regression separately; diagnosis
  does not authorize an unrelated score/FPL production change in this gate.
- Preserve correct production transport and all owner settings; exact variant,
  source/executable and physical receipts are in release138. Remove owned
  temporary build/test/private copies and UI runner; end task-bound keep-awake.

## 2026-10-11: Focused CS football identity repair and real Jet iPad regression

- Owner requests proper CS matching, a regression and iPad tests only. Preserve
  all other behavior; no new Home/Watch Two/PiP/FPL/fixture, trust, phone,
  TestFlight, Git publication or cloud changes.
- Fresh public metadata offers Hull City–Everton at13:00UTC. The iPad also has
  Hull City AFC–Everton FC at that time; the old CS key rejects legal names while
  accepting plain names. CS is enabled and local failures show no exact match.
  The originally tapped duplicate is unknown; do not claim a deliberate removal.
- Reuse the main catalog's unique reviewed football club identities. Preserve
  both teams, sport,15-minute bound, complete unknown names, squad qualifiers
  and conflicting-ID rejection; non-football and transport remain unchanged.
- Six new unit methods cover positive and rejection boundaries; three fail on
  the old matcher. Complete simulator-free gate passes1151/two optional skips,
  source tools, goldens and unsigned Release. Independent review passes.
- Final real-feed physical gate selects the suffixed row and hard-fails if its
  expected picker disappears, rather than skipping the regression. It passes
  with CS1–CS6 visible. Separate same-match CS1 native progress and responsive
  controls pass: two physical passes/no failures/skips. Muted/brief evidence is
  not audio, sustained playback, PiP, all variants or Watch Two proof.
- Signed private138/source comparison/readback pass; source/executable receipts
  are in release138. Preserve user settings/account, remove owned temporary
  outputs/UI runner and end task-bound keep-awake. Shared121 and phones125 stay.

## 2026-10-10: Researched watchdog plan and private CS contract qualification

- Owner requests deep research and a plan for proactive detection and bounded
  small repairs, with the Mac awake only through the active task. Reuse cloud
  collection and GitHub verification; routine monitoring must work with the Mac
  off. `operations/Fotty-Watchdog-Plan.md` is the durable reviewed proposal, not
  activation, paid agent execution, publication, deployment or TestFlight.
- Separate admitted-source contracts, accepted fixture integrity, actual native
  experience and missing-observer detection. Persistent quiet incidents need
  exact revisions, stable keys, recovery receipts, retention ceilings, expiring
  leases/fencing and one repair owner. Automatically safe runtime recovery and
  independently reviewed repair preparation are distinct from production writes.
  Trust, identity, coverage, privacy, spending and distribution remain gates.
- The already approved CS/iPad repair carries the maintainer's bounded public
  request headers into the existing guarded proxy. Eight regressions plus fresh
  Catalyst1093 passes/two optional skips and iOS Release compilation pass.
  No credentials/cookies/custom or response headers, host/path/TLS relaxation,
  source activation or fixture invention. Private137 is installed on Jet iPad;
  owner phones125 and shared TestFlight121 remain unchanged.
- Exact Calgary–Anaheim CS2 briefly proves selected-source native progress and
  responsive controls; CS1 fails and falls back. The local ring then records a
  CS2 decoded-stage unknown failure/retry. Do not convert that brief gate into
  sustained playback acceptance or infer a precise provider/AVFoundation cause.
  Failed/skipped physical gates remain dated evidence in release137/136, not
  silently waived. Test-only canaries distinguish input/runner interference from
  app defects and bind PiP evidence to the actual qualified source/item/attempt.
- Final private137 harness source/binary have a separate verified pre-build
  receipt. Home/Matchday/Search passes; CS PiP fails before start because local
  records prove an actual CS2 failure/new attempt. The additional passive
  Watch Two canary loses runner/session after76 seconds, with Fotty activity
  before disconnect and no matching crash/Jetsam cause. Result: one pass/two
  failures/no skips. Preserve these limits; no speculative product/hook changes.
- No telemetry upload, Git publication, cloud activation, device reset, phone
  install or TestFlight. Retain exact source recovery receipts, remove only owned
  test/build artifacts and runner, and release task-bound keep-awake at completion.

## 2026-10-10: Home projection and audio-session ownership cleanup

- Owner requests Home coordinator/audio cleanup and proper tests, expressly no
  TestFlight. This is source/local verification only, with FPL features paused;
  no device install, backend deployment, Git publication, data reset or spending.
  Source version128 remains unchanged and is not the installed128 executable.
- Reuse the verified stabilization-after recovery bundle as the before boundary.
  Add `HomeProjectionCoordinator` with one immutable base/scope packet, exact
  catalog/score/clock/selection keys, facts-cache reuse and request generations.
  Stale/cancelled entrants cannot revoke accepted pending work. Scope edits retain
  the accepted base revision; pending work derives latest scope at atomic commit.
  Keep cooperative sixteen-row stages on MainActor, not detached non-Sendable
  values. The view retains structured task, filters, layout, modal/navigation and
  single/two-match Watch ownership; independent baseline comparison confirms it.
- Apple performance guidance informs serialized off-main audio preparation.
  Launch/navigation/route configuration does not activate audio. Use SDK27 async
  activation and serial-queue blocking fallback on supported older runtimes;
  coalesce demand, cancel individual waiters and reprepare after media-services
  reset. AVPlayer/WebKit/PiP/transport state retain their native owners. Typed
  stage/code errors stay local; no new deactivation or telemetry-upload policy.
- Recheck current attempt/source/player/item/intent/lifecycle/error after awaits.
  Pause/replacement/dismissal/terminal failure revoke permission; separate PiP
  preparation cannot cancel pending Play. Resume first starts without a stuck
  spinner; two-pane resume uses current audio focus. Start provider clocks only
  after prepared Play/navigation. Deferred Web navigation seeds current pause,
  suspension/mute/fill intent and respects provider-owned audio. Independent
  review finds and fixes terminal late-Play and fresh remote-Play false-playing
  races; preserve explicit Retry's existing new-attempt path and retained intent.
- Add44 executed behavioural regressions: ten Home,23 audio and eleven Web tests.
  Controlled suspension covers cancellation/replacement/reset/PiP/background/
  terminal/remote commands; Web tests execute production-emitted JavaScript.
  Final freshly compiled Catalyst1036 total/1034 pass/two existing optional skips/
  zero failures,52 offline tooling tests, source membership/version/catalog/
  provider identity/diff gates and unsigned generic iOS Release pass. Native
  checksums are unchanged across the final gate. Six earlier audio runtime
  warnings no longer appear; four offscreen MatchReminderTests focus warnings
  remain, not proven native focus defects. No device sound/latency/PiP claim.
- Refresh architecture, risks and developer handoff. Preserve a verified local
  `backups/release-source/ownership-20261010-after` bundle, not binary provenance.
  Two sequential current-source gates reuse the same bounded one-job output path;
  owned DerivedData/results/runner and review temporaries are removed. About30GiB
  remains free; unrelated user artifacts/caches are preserved. Native audio route,
  interruption/PiP and responsiveness acceptance remain separate device gates.

## 2026-10-10: Source stabilization and a reproducible developer handoff

- Owner approves the proposed maintenance pass after discussion of code
  readability and badge regressions. Scope is source/local verification only;
  no FPL feature work, Git publication, device install, backend or TestFlight.
- Capture and verify a local recovery baseline before edits without changing the
  source index/refs or discarding the large pre-existing dirty tree. Preserve
  ignored credentials/data and distinguish capture from historical binary proof.
  Retain bounded before/after recovery bundles rather than build artifacts.
- Mechanically separate image transport/cache/decode into `Core/Images`, ordered
  selection/view state into `Design/CachedAsyncImage.swift`, and independent Home
  policies, Details and motion into dedicated Dashboard files. Independent
  comparisons against the before bundle confirm unchanged moved declarations
  and remaining owner logic. Do not relocate private tasks/state or weaken actors.
- Register all five new Swift sources explicitly. Add the bounded offline native
  membership gate with32 synthetic tests and run it in the existing iOS CI script;
  extend trigger paths. Preserve existing behavioural tests and extend negative
  Home guard scope to the extracted files. No source-string assertion is dropped.
- Current-source Catalyst992 total/990 pass/two existing optional skips/no failure,
  unsigned generic iOS Release,52 combined offline tooling tests, catalog/identity/
  version checks, shell syntax, actionlint and diff checks pass. Six audio and four
  offscreen-focus runtime warnings remain review evidence, not native hang/focus
  diagnoses. Device acceptance is unchanged from128; no new UI/playback claim.
- README and `docs/Fotty-Developer-Handoff.md` identify source recovery, current
  ownership, local commands and next safe seams. Home's live coordinator, Watch
  lookup state, cross-sport brand service and audio-session activation need focused
  tests/measurements before deeper cleanup. No blanket rewrite or LOC-only defect.
- Sequential one-job gate reused one bounded directory; owned DerivedData/results/
  workflow-lint binary and review clones removed. About30GiB free; no unrelated
  artifacts/caches removed. Native version remains128, not a new release candidate.

## 2026-10-10: Finished-match receipts and shared badge selection in private128

- Owner requests proper false-LIVE repairs and Jet iPad testing, then reports
  wrong Man United and multiple badges. No TestFlight, phones or backend rollout.
  Production schedule already has explicit final facts for560592/560595; use
  native reconciliation rather than infer a result from time or disappeared data.
- Official PL mapper retains explicit recent finals. Repository/service separate
  source receipt from attempts, retain bounded accepted terminal identity, revoke
  stale/failed/empty active authority, use post-await clocks and preserve Details
  enrichment. Home retains terminal vetoes before deduplication; Matchday/Watch/
  reminders share terminal policy. Notification history survives temporary unknown
  or empty feeds without replaying kickoff/goals; explicit final still advances it.
- Badge cause: shared CachedAsyncImage allowed warm fallback cache to skip an
  uncached higher-priority URL, and unkeyed image state survived row/candidate
  changes. Provider Man United66.png visually correct; no provider-ID cache
  collision established. Ordered selection, primary-only immediate cache, full
  URL-list state identity and cancellation fix all shared consumers. Official PL
  stable-code crests are carried through mapper/repository and guarded Home
  precedence without overriding schedule identity or borrowing cup/youth facts.
- Final current-source units:992 total,990 passed,two existing optional skips,
  zero failures. Signed iOS Release/strict signature/app+extension128, catalog,
  version/provider vectors/proxy tests/diff checks pass. Jet in-place sequence2132
  and installed2.0.1(128) readback pass. Both real-feed physical journeys pass,
  no skips/failures. Actual landscape Home/Matchday badges checked after scores
  load and navigation; deterministic tests cover warm-cache/reuse/terminal races.
- Replace the first private128 binary with final hash recorded in release128.
  The initial runner timeout was repeated AX descendant enumeration, not proven
  app crash; bounded fixture checks pass. Optional verbose test diagnostics stay
  off; app telemetry/permissions unchanged. No data reset, new packages, backend
  deployment, publication or shared release. Keep127's playback/QoE limits.
- Evidence and cleanup scope: `docs/releases/Fotty-2.0.1-128.md`. Only the owned
  runner, temporary physical scheme and sole1.9GiB build/result gate removed;
  absence independently verified,31GiB free. Ordinary Fotty128 remains running
  as9217; later mirror still shows correct Man United/Tottenham with loaded scores.

## 2026-10-10: Whole-app performance repairs and private Jet iPad127

- Owner approves the whole-app open-source review recommendations in priority
  order, then private Jet iPad testing; expressly no TestFlight. FPL stays paused.
  Shared121, phones125, backend and spending/privacy policy remain unchanged.
- Implement all thirteen accepted items: bounded native transport/CS redirects,
  decoded-frame handoff, independent Watch Two attempts/continuity, score polling
  leases, resident badge freshness, independent provider/fixture publication,
  revision-keyed Search/Home facts, date/duplicate-ID indexes, two shared image
  decode permits, cached quality persistence, bounded asynchronous backup import,
  scalar pull-only native QoE and deterministic cancellation/clock regressions.
  Applicable OSS patterns are references, not new dependencies or copied engines.
- Actual iPad profiling justified follow-up repairs: unchanged receipts skip
  duplicate merges; fixture metadata is prepared once; Home/Search/Matchday use
  cancellable MainActor checkpoints and atomic exact-key publication. Matchday
  exposes flat lazy rows with stable section/column/member identity. Do not move
  non-Sendable service/event objects to an unsafe detached task to hide a hang.
  Apple UI guidance also led to reachable child controls and truthful failed-pane
  audio availability, without a redesign or invented fixture/playback evidence.
- Current-source Catalyst logic gate:941 total,939 passed,two existing optional
  skips,zero failures. Signed iOS Release/strict signature/app+extension127,
  version/catalog/provider-identity gates and Jet iPad in-place readback pass.
  Final physical Home/Matchday/Search and Watch Two90s soak:two passed,no skips
  or failures. No account/source reset; latest binary hash is in release127.
- Synthetic9500-row decode/dedup/discovery/Search workload is ~90% lower;
  not whole-app FPS. Final46.788s trace captures repaired Matchday work outside
  hangs. Sole521ms hang is native keyboard focus/input views, without distinctive
  Fotty frames. This does not prove all stutter eliminated. Two decoded panes,
  alternate-source switching, native sound/PiP/background and WebKit network QoE
  are not newly qualified; final96 pull samples report measurements unavailable.
- Keep evidence/results/limits in `docs/releases/Fotty-2.0.1-127.md`; remove only
  the owned temporary physical scheme, test runner and bounded gate after use.
  Cleanup verified:runner absent,~2.9GiB gate/scheme removed,31GiB free. Ordinary
  Fotty127 remains running on Jet iPad; visual-confirmation replay also passed.

## 2026-10-10: Playback stages and open-source performance review

- Owner approves local failure-stage tracking plus a named Jet iPad install;
  adds open-source research, not a wholesale engine/dependency migration.
  Native app/widget advance to private126; shared121 remains unchanged.
- WebKit reports bounded, typed document-load/media-observed/media-ready,
  decoded/buffering, document/media failure and process-termination observations.
  Navigation failures retain only numeric platform codes. Passive JS observes
  eligible media, never drives playback; stale attempts and unrelated post-start
  documents cannot annotate the selected stream. Loaded/ready is not decoding.
  Native startup records readiness/decoded milestones in the same local context.
  Failures carry last_observed_stage, not an invented causal verdict. Opaque
  provider media and child/ad observations before ownership limit interpretation.
- Same 250-record/14-day retention and no new upload. New callbacks do not alter
  source admission, startup/recovery grace, provider controls or PiP. Frequent
  duplicate stages are suppressed; buffering becomes eligible again on recovery.
- Verification: 862 native tests, two skips, zero failures; catalog/identity checks
  and signed iOS Release app/extension126 pass. Jet iPad in-place install sequence
  1868 and independent2.0.1(126) readback pass; launched process8092 observed.
  No new live-play/UI acceptance claimed. Owned output removed;33GiB free.
- Research inspected primary repositories/source, without cloning or installing
  packages: Mux AVPlayer monitoring/event cancellation, Nuke pipeline, Pulse,
  Swiftfin's AVPlayer adapter and Point-Free clocks/concurrency extras. Priorities:
  richer typed native QoE evidence; injectable clocks for deadline/cancellation
  tests; measure badge-cache performance before considering stable Nuke13;
  profile synchronous quality-store serialization before changing persistence.
  Pulse URLSession logging is not transparent WebKit networking visibility;
  raw request/header capture would need a separate privacy review. Swiftfin's
  adapter itself contains buffering TODOs, so popularity is not correctness proof.
  Concurrency Extras' serial executor is test-only, not a production optimizer.
- Primary references: https://github.com/muxinc/mux-stats-sdk-avplayer,
  https://github.com/kean/Nuke, https://github.com/kean/Pulse,
  https://github.com/jellyfin/Swiftfin, https://github.com/pointfreeco/swift-clocks,
  https://github.com/pointfreeco/swift-concurrency-extras. No measured app speedup
  or installed dependency is claimed by this research.

## 2026-10-10: Local playback correlation, source-only

- Owner requests actionable tracking for iPhone/iPad playback differences.
  Existing iPad125 local records show repeated web startup timeouts and failover;
  document loading or a provider outage is not a proven cause. Some provider
  labels are lost to the existing punctuation filter; retries had no parent link.
- Normal playback and each Watch Two pane now retain a watch-session UUID,
  attempt ordinal/previous attempt, source UUID, opaque endpoint digest,
  device family and numeric OS version. Source failures, web retry scheduling
  and session closure are local quality events; transport/recovery is unchanged.
- No raw URLs, headers, credentials, fixture names or new telemetry upload.
  Existing 250-record/14-day attempt-cohort retention remains; older parts of
  a watch session can expire. Endpoint digests change with signed URL rotation
  and do not distinguish header-only differences or prove broadcaster identity.
  Source UUIDs are local choices, not cross-device stable identities.
- Focused Catalyst tests:138 executed,one skipped,zero failures; unsigned iOS
  Release compile passes. Owned build output removed;33GiB free. This is not
  device playback acceptance or a repair of the underlying iPad timeout.
  Installed125/shared121 and backend are unchanged; no distribution authority
  is inferred from this source-only tracking pass.

## 2026-10-10: Install latest verified private125 on Jet iPad

- Owner requests the latest iPad update; connected inventory confirms Jet iPad
  Air4/iPadOS27.0.1. Native source matches the retained125 receipt. Rebuild that
  frozen source with pinned official Xcode27.0/27A266a, signed Release/jobs1.
  Signature, version and receipt checks pass; no app/source behavior changes.
- In-place installation sequence1860 and independent2.0.1(125) readback pass.
  Ordinary launch remains running after30seconds, main PID7648. No uninstall,
  reset, account copying, simulator or UI-test helper. Saved-data equivalence,
  actual screen interactions/playback/PiP remain unqualified by this launch check.
- Sole owned370MiB temporary source/build gate removed;33GiB free. Shared121,
  other devices and backend unchanged. See release125 for executable hash.

## 2026-10-08: Install private125 on Kiel's confirmed iPhone11

- **Authority**: Owner requests direct-install fallback for pending TestFlight
  email, confirms the named iPhone11 belongs to Kiel, then completes Developer
  Mode/restart. No other target, TestFlight release, role change, Git publication,
  backend deployment, paid-policy or FPL feature work.
- **Provenance**: Rebuild the retained125 frozen source with official Xcode27.0,
  signed optimized Release/jobs1 and explicit target provisioning. Both source
  comparisons, compiled app/widget identities/versions/floors, target profile
  inclusion/expiry/team, strict signatures and blank provider keys pass. No new
  runtime source/version change. See release125 for source and binary hashes.
- **Evidence**: Fresh inventory confirms iPhone11/iOS26.5.2,26.4-compatible,
  wired/paired and Developer Mode Enabled. Fotty initially absent; installation
  sequence5708 and two independent2.0.1(125) readbacks pass. A rejected empty-env
  CLI launch option is corrected to normal launch, without rebuild/reinstall.
  Main PID595 remains at10/20/30seconds. Device Hub requires iOS27 to mirror
  with this Mac; stop the sharing attempt on26.5.2. No UI, playback/audio/PiP or
  performance acceptance claim; Fotty's own compatibility floor remains26.4.
- **Distribution**: Live Apple group now has12 testers after Kiel's earlier
  addition; his TestFlight status was Invited and reinvite submitted. Neither
  mailbox delivery nor TestFlight acceptance is proven by this direct install.
  Shared121, owner125, Jet iPad120 and production Worker remain unchanged.
- **Cleanup**: Sole owned368MiB temporary gate removed; about15GiB free;
  existing source receipt retained. No uninstall, data copying/reset, helper or
  unrelated cache cleanup. Leave the normally launched app for Kiel to use.

## 2026-10-08: Install private usability build125 on Jelani’s iPhone

- **Authority**: Owner requests phone deployment for testing. Only Jelani’s
  iPhone15ProMax; no TestFlight, other device, Git publication, Worker deployment,
  new feeds, paid-policy changes or FPL feature work.
- **Packaging**: App/extension/source metadata advance coherently to2.0.1(125).
  Reuse the completed852-pass/two-optional-skip exact functional native gate;
  seven offline version tests and fresh catalog/project/syntax checks pass.
  Extract the synthetic reminder persistence namespace into a local test constant
  to clear a confirmed scanner false positive without changing its value/assertions
  or scanner rules. Capture1002-file frozen source; compare before installation.
  Official Xcode27.0/jobs1 signed Release, strict signatures, compiled versions
  and blank provider keys pass. See release125 for frozen/source/binary hashes.
- **Device**: Wireless discovery unavailable; cable then requires same-device/Mac
  trust restoration completed by owner. Fresh paired/unlocked identity is correct.
  In-place install sequence2624 and independent2.0.1(125) readback pass. Normal
  argument-free launch remains running at10/20/30seconds. Device Hub shows new
  dark Home, retained Cricket scope, readable grid and four native glass-tab labels.
  Apple UI acceptance guidance keeps this launch-screen evidence separate from
  full interaction, accessibility, saved/reminder, playback/PiP or measured speed.
- **Cleanup/handoff**: Failed324MiB and successful326MiB owned build roots removed;
  about15GiB free; intentional19MiB source receipt retained. No uninstall/reset,
  UI-test helper or unrelated cleanup. Fotty is left open for owner testing.
  Shared121, Jet iPad120 and production Worker remain unchanged; backend repairs
  remain staged. No broad visual/performance acceptance claim.

## 2026-10-08: Complete source-only Apple-native usability repairs

- **Authority**: Proceed with the focused usability audit repairs. Source/local
  verification only; no device interaction/install, Git publication, Worker
  deployment or TestFlight. FPL feature work remains paused. Preserve the large
  pre-existing dirty worktree and installed/shared binaries.
- **Design**: Apple UI guidance shaped readable reflow, minimum control targets,
  honest labels and explicit filter feedback. Preserve Fotty's club badges,
  sport artwork, native tabs and inline future-match countdowns. No dependency,
  wholesale redesign, extra glass layer or automatic reminder opt-in.
- **Identity**: The observed Arsenal/Arsenal FC duplicate has a unique exact-start
  reviewed football join. Require reviewed clubs, senior squad and compatible
  competition evidence; reject held proof, cup/youth/women contradictions and
  multiple official candidates. Preserve sources and explicit provider aliases;
  typed identity cannot move to another official fixture. Saved and reminder
  continuity retains opaque IDs, accepted facts and notification intent revisions.
  Reverse provider aliases require the same start. Quarantine stays quarantined.
  Explicit removal/cancellation revokes corresponding legacy requests; passive
  refresh does not delete bookmarks or opt-ins. Concurrent aliases share one intent.
- **Home/Search/Matchday**: Show the active filter scope and return to results only
  after explicit Home filter changes. Empty-copy windows match the real six-hour
  or personalized three-day projection. Search future results and unplayable
  Matchday/channel rows offer Details with visible Save and existing opt-in reminder
  controls. Details distinguishes listed, missing, unknown-start and stopped
  broadcasts without claiming successful playback or asking live users to wait.
- **Secondary screens**: Focus/enlarge exists only in supported wide landscape;
  one-source Retry acts directly. Recovery scrolls within the remaining pane.
  Portrait player identity wraps, and channels do not invent opponents. Match Hub
  removes duplicate freshness/pre-match promises for live games. Settings exposes
  truthful Premier League/foreground alert scope separately from scheduled reminders,
  real source loading/empty/failure recovery and subdued passive values. Feedback
  explicitly says copied, not sent; no unverified TestFlight deep link was invented.
- **Verification**: Official Xcode27.0/jobs1, simulator-free full native suite:
  852 pass, two existing optional skips, zero failures; unsigned generic iOS Release
  passes. Version2.0.1(124), generated football catalog, provider identity vectors,
  project lint and whitespace checks pass. New regressions exposed and closed
  exact-ID typed-to-raw saved continuity; the one-shot concurrent test callback was
  corrected without weakening its assertions. Existing Catalyst audio/focus warnings
  are not physical iOS responsiveness proof. No zero-jank or new PiP qualification.
- **Handoff**: Source remains124, owner iPhone124/Jet iPad120/shared121 and production
  Worker unchanged. Native visual/interaction acceptance is a separate named-device
  gate. Sole temporary gate reused through corrections and removed by trap;
  failed output/crash attachment/result bundles are removed; about15GiB free.

## 2026-10-06: Install private native all-sport repairs on Jelani’s iPhone124

- **Authority**: Owner requests deployment to phone for testing. Only Jelani’s
  iPhone15ProMax; no Worker deployment/publication, TestFlight, other device,
  new feeds, paid policy or FPL feature work. Backend repairs remain staged.
- **Packaging**: Live ASC list still shows shared121. Advance source app/extension
  to2.0.1(124), capture998-file pre-build receipt and compare before installation.
  Recent818-pass/two-skip exact native-code gate is reused; fresh coherent version,
  generated catalog, three-feed live metadata identity and signed optimized iOS
  Release pass. Official Xcode27.0/27A266a/jobs1, strict signatures and blank
  embedded provider keys; no simulator or device UI-test helper.
- **Device**: Fresh named-device inventory/lock read succeeds; install in place
  without uninstall/reset, database sequence2504. Independent app inventory reads
  124. Ordinary launch and45-second process hold pass. Physical UI/font/reminder,
  live playback/audio/PiP acceptance remain separate; no account equality claim.
- **Cleanup**: Sole320MiB build root removed by trap;26GiB free. Small19MiB
  history-free recovery receipt retained intentionally. Shared121/Jet iPad120/
  production Worker unchanged. See `docs/releases/Fotty-2.0.1-124.md` for hashes,
  code scope and backend dependency; leave the iPhone launched for owner testing.

## 2026-10-06: Complete source-only all-sport audit repairs and shared row cleanup

- **Authority**: Owner says proceed with required fixes after the all-sport audit.
  Implementation/local verification only: no Git publication, Worker deployment,
  device installation, TestFlight, new feeds/flags, paid-policy or FPL changes.
  Preserve the large pre-existing dirty worktree and current installed binaries.
- **Fixture admission**: Isolate recognized missing/status/correction disputes per
  record while healthy competitions and unrelated rows advance. Held facts and
  original receipts remain unchanged; per-competition failures/backoff remain
  visible. Schema1 optional verified/held markers reject null/unknown values and
  cannot bypass transport/schema/scope/publisher-provenance barriers. Empty
  success advances the replay fence. Correction confirmation is per fixture,
  independent of unrelated additions. Partial HTTP200 requires validated fresh
  verified records; unavailable row overrides expire after30minutes.
- **Additional integration defects**: Independent offline review reproduced
  opaque-ID replacements duplicating a native identity, football-data publisher
  IDs moving competition, and terminal resurrection under replacement IDs.
  Preserve originals as held, withhold contradictory replacements, and advance
  unaffected records; never guess aliases/migrate accepted fixture identities.
  Raw semantic/publisher duplicates remain full-collection barriers. Distinct
  starts/participant identities/squads remain independent. Numeric latest-receipt
  selection fixes mixed fractional/nonfractional UTC ordering without renewal.
  These are verified synthetic failure modes, not claims of production incidents.
- **Collection/monitoring**: Scoped provisional pending dates drive bounded hot
  polling but never public fixtures/countdowns/reminders. Fresh terminal/postponed
  publisher evidence is compared with accepted active facts. Fresh current facts
  against an old quiet receipt require refresh, not a definitive omission claim;
  identical consecutive redacted fact evidence must repeat/escalate after grace.
  Same-publisher MLB/NHL/WNBA reconciliation remains distinct from independent
  publisher corroboration and cannot activate an unpublished lane.
- **Native continuity/status**: Cache merges preserve watermarks and demand newer
  correction/status receipts; held starts cannot create or retain reminders.
  Bookmarks remain. Fresh independently matched provider receipts allow Broadcast
  listed, not inferred LIVE. Exact unique verified MLB/NHL joins support actual
  plain-category feeds and reviewed name aliases, with explicit local provider-ID
  aliases for playback/bookmark/reminder continuity, including later terminal
  receipts. Conflicting leagues/squads/dates and ambiguous doubleheaders reject.
  Details/landscape controls share certainty policy; held Cricket Matchday and
  normalized Motorsport search agree with Home. Generic channels prove no match.
- **UI**: Apple UI skill/HIG informed readable identity-first upcoming rows:
  countdowns move below identity, compact reminders keep44-point targets, Watch
  stays beside playable rows, and channel cards lose repeated type/status text.
  Preserve badges, artwork, themes, focus/Undo ownership and native navigation.
  Rendered320/375/430/788-point schedule/channel variants were inspected. Hosted
  accessibility layout is calibrated separately: detached ImageRenderer excludes
  some platform-backed content, per [Apple's documentation](https://developer.apple.com/documentation/swiftui/imagerenderer).
  These checks do not establish physical reminder/large-text/playback acceptance.
- **Verification**: Final full gate818 Catalyst tests pass/two optional skips/zero
  failures, provider identity preflight and generic unsigned iOS Release pass.
  Full367 web/backend units (including synthetic workerd/DO tests), TypeScript,
  lint, Worker dry-run and isolated webpack production build pass. Independent
  backend recheck passes88 overlapping tests; focused138 overlap the full suite.
  Three obsolete test expectations were repaired to express held-start certainty,
  unknown baseball duration and a genuinely newer per-row receipt, not by weakening
  correct production guards. Existing Catalyst audio-session/detached-focus runtime
  warnings remain; no new device-performance or zero-warning claim.
- **Boundaries/cleanup**: One bounded output path/jobs1; no simulator or heavy
  parallel builds. DerivedData and isolated web build copy are removed, then
  owned screenshots/logs are cleaned. Production6399f52d/source cricket-isolation-1,
  shared121, iPhone123 and Jet iPad120 stay unchanged. Source build versions remain
  123 until a separately approved packaging gate; bump native/Worker source IDs
  and capture the immutable source receipt before any later install/deployment.

## 2026-10-06: Isolate disputed cricket records and align Home destination counts

- **Authority/scope**: Owner says fix properly, then explicitly approves the
  focused protected Worker publication/deployment plus matching private build on
  Jelani’s iPhone. No shared TestFlight, other device, paid/new-feed activation or
  FPL feature changes. Preserve the large pre-existing dirty worktree.
- **Cause**: Three disappeared accepted records and two unflagged future kickoff
  changes froze the whole ICC60 cohort atOct3, blocking fresh unrelated LIVE and
  terminal updates. Separately, sport tiles counted the global catalog while
  taps obeyed retained CPL/Channels and Home-interest filters. Willow programme
  identity is unknown; generic channel playback does not prove a named fixture.
- **Contract**: Keep complete collection/identity/watermark/bound gates. Isolate
  recognized record disputes, retaining exact facts/receipts as held, while fresh
  unaffected rows are verified. Preserve failed cohort coverage, failures and
  backoff. Revision hash includes markers. Native schema1 handles legacy absent
  markers, rejects invalid markers, fences cache watermarks and removes confident
  held countdowns/reminders without deleting bookmarks. Only fresh matched
  provider descriptors grant separate listing receipts, never generic LIVE.
  Cached sport summaries describe their actual destination without clearing
  saved preferences or adding per-tile render scans. Apple UI skill/HIG scope
  guidance informed that preference-preserving design, not a screen redesign.
- **Publication**: Six backend/monitor files only, normal protected PR39 merge
  `243f9bb`; all PR and main Web/quality/CodeQL gates pass.79 focused units and
  primary333 web tests pass. Exact merged Worker dry-run/deployment6399f52d
  succeeds with source2026-10-06.cricket-isolation-1;100% version and all17
  binding names/types,4DO identities, vars/secret names/types/rate limits and
  */5 cron are verified unchanged. Exact-version scheduled16:15:59 succeeds.
- **Production**: Normal due receipt16:16:30 UTC has77 rows/72 verified/five held/
  two fresh verified live.270987 is live,274310 finished; five disputed facts and
  Oct3 receipts remain unchanged. ICC68 stays unavailable/650 failures, so issue37
  remains open. Current-match staleness alert clears; coverage/failure alerts do
  not. Bounded CWI check matches its one supported current/next-day fixture.
- **Native gate**:799 Catalyst passes/two optional skips/zero failures and unsigned
  Release pass after fixing a missing SwiftUI return. Signed private123 app and
  extension, strict signatures and blank provider keys pass. First install loses
  access as the phone locks; its output is cleaned. Rebuilt123 installs in place,
  verified in device inventory. Phone locks before normal launch-hold; UI checks
  await unlock. No erasure or record-equality proof.27GiB free, all owned build
  output cleaned. Shared121/Jet iPad120 unchanged; see release123.

## 2026-10-06: Install private122 on the named owner iPhone

- **Scope**: Owner reports the phone connected; finish the authorized private
  build/install/normal launch, not shared TestFlight or other device testing.
- **Connection**: Exact iPhone15ProMax/iOS27.0.1 is visible but initially unpaired.
  Standard CoreDevice pairing succeeds; fresh details show connected/paired,
  Developer Mode enabled and wired transport. No cable demand, unpair/reset,
  alternate device or network configuration change.
- **Evidence**: Source versions remain coherent2.0.1(122); independent read-only
  packaging review finds no blocker. Rebuilt signed generic-iOS Release with
  pinned official Xcode27/jobs1 passes strict deep signatures and compiled
  app/extension122 checks; embedded provider keys are blank. Device inventory
  reads121 before the normal in-place install, which succeeds. A diagnostic-only
  column error is corrected to bundleVersion; installed122 is then verified
  without another install/build. Normal launch and repeated process checks pass.
  Current native screenshot shows Home/catalog/badges/sport art/navigation.
- **Limits/cleanup**: No records are erased or compared; do not claim data-equality
  proof. Animated lookup, Cancel/Undo, light/dark/large text and playback remain
  owner acceptance, not launch proof. Owned build output and screenshot are
  removed;27GiB free remains. Shared121/Jet iPad unchanged. See release122.

## 2026-10-05: Prepare private122; named iPhone wireless installation blocked

- **Authority**: Owner requests the new Inline/all-sports UI batch on Jelani's
  iPhone for testing. The usual connection is wireless; unavailable discovery
  does not require a cable. No other device or shared/TestFlight release.
- **Provenance**: Increment only app/extension build metadata to2.0.1(122),
  preserving bundle identities and signing team. Source preflight finds no new
  data-reset path; do not claim installed records were compared or retained.
- **Evidence**: Coherent four-configuration version verification, seven verifier
  tests and project lint pass. Signed generic-iOS Release with pinned official
  Xcode27/jobs1 passes; strict deep signatures, compiled app/extension122 and
  blank embedded provider keys are verified. Prior source batch has786 passing
  tests/two optional skips and native artwork evidence, not new device proof.
- **Actual outcome**: Paired owner phone has Developer Mode enabled but remains
  unavailable/offline in bounded CoreDevice/xcdevice/xctrace checks. Pre-install
  inventory fails4016; installation is never attempted and no launch occurs.
  Await an unlocked phone on the Mac's local Wi-Fi, then retry this same gate.
  No device substitution, re-pairing, reset or network configuration changes.
  Cleanup trap removes all owned build output on failure;28GiB free remains.
  Shared121 and previously installed owner121 are unchanged. See release122.

## 2026-10-05: Finish the all-sports Inline loading motion family, source-only

- **Scope correction/authority**: Owner rejects the cricket-only animation pass
  as incomplete and says fix. Apply its calm quality standard across the whole
  known sport-art family, not a recolored ball. Local implementation/checks only;
  leave the ended iPhone gate alone. No install, TestFlight, Git publication,
  provider/backend, paid-service or FPL feature change. Shared2.0.1(121) stays.
- **Native contract**: Preserve the approved nonblocking Inline panel, truthful
  loading status and reachable Cancel. Equipment stays within its160x120 logical
  canvas and the51.8x38.85 artwork inside a52-point Inline slot. No animation
  completion delay, extra gesture capture, sound, network asset or new library.
  Retain visibility/scene/Reduce Motion/Low Power guards and the30fps ceiling;
  this is a scheduling limit, not a measured physical-device frame-rate claim.
- **Implementation**: Football rolls, basketball/tennis use smooth eased contact,
  baseball has a restrained seam arc, oval balls retain distinct NFL/rugby rhythms,
  hockey glides with a bounded trail, motorsport uses a calmer track loop and
  combat gloves a softer approach. Preserve cricket's approved gentle motion.
  Add original explicit table-tennis paddle/net, golf green/flag/dimpled ball,
  darts board/flight, volleyball panels, handball grip panels, lacrosse stick/net
  and cycling wheel/crank art. Multi-sport composition and honest unknown-category
  symbol fallback get bounded motion. Champions League keeps verified identity
  admission with quiet original stadium lighting, not an official UEFA logo.
  Normalize UI aliases and keep table tennis before tennis / NFL before soccer;
  align ping-pong and Formula1 discovery aliases. Add light/dark edge contrast
  and stronger source-level Increase Contrast treatment. Watch Two's preparation
  and per-pane waits use the same artwork with hit testing disabled; playback,
  source admission/selection, transport, PiP and fixture classification unchanged.
- **Evidence**: Final simulator-free full gate passes788 tests (786 passed,
  two optional skips), unsigned generic-iOS Release, parser/plist/whitespace.
  Inspect all eight current native ImageRenderer sheets:20 profiles, four phases,
  light/dark,160x120 and exact Inline scale. No observed blank/mismatched equipment
  or clipping; all bounds/loop/suppression/pixel tests pass. These are native art
  renders, not actual phone/iPad screens or an observed continuous animation.
  Independent source review confirms prior alias, sizing, clipping and two-match
  coverage findings resolved. Final alias checks, parser/plist and scoped
  whitespace checks pass. The Catalyst host reports legacy audio-activation and
  out-of-body FocusState diagnostics in existing player/reminder tests; this is
  not a warning-free or measured-performance result. Owned DerivedData, result
  bundles, logs and contact sheets are removed;28GiB free remains. No physical
  device or shared distribution changed.
- **Open acceptance**: Physical device light/dark, Increase Contrast, Reduce
  Motion/Low Power transitions, perceived motion/legibility, navigation and
  real-player controls remain a separately authorized gate. No claim of improved
  measured responsiveness or release acceptance. Relevant current Apple guidance:
  [Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
  [Loading](https://developer.apple.com/design/human-interface-guidelines/loading).

## 2026-10-05: Implement the approved Inline feedback direction, source-only

- **Authority**: Owner chooses Inline after the original interactive motion
  preview and says proceed. Native implementation/local checks only; no device
  installation, TestFlight, Git publication, backend or paid-service change.
  Leave the owner-ended iPhone gate alone. Shared2.0.1(121) is unchanged.
- **Native contract**: Keep the catalog visible during stream lookup. A compact
  bottom safe-area panel above navigation carries sport artwork, current status,
  requested match/pair and a real44-point Cancel; no full-screen dimmer or raw
  provider diagnostics. Anchor outside Home's NavigationStack destinations so
  lookup feedback also survives opening the full lineup. Use semantic text,
  wrapping, accessibility stacking and selected browsing appearance; iPad's
  temporary panel has a720-point readable width rather than stretched text.
  Success confirmation stays beside the reminder action with one-use Undo and
  Dismiss, never an automatic notification opt-in or timed dismissal.
- **Implementation/safety**: Reuse current SwiftUI/Canvas and press feedback, not
  new Lottie/Pow/PopupView runtime packages. Cricket gets gentle bounded bounce,
  seam rocking and warm original art; retain30fps/visibility/scene/Reduce Motion/
  Low Power guards and the existing feedback-frame window, no forced completion
  delay or sound. Nonblocking lookup exposed independent single/multi lanes:
  admit one at a time, freeze requested pair titles and disable playback/selection
  controls, not browsing/filtering/saving/reminders. Both Cancel paths invalidate
  tasks/UUIDs. Opening another modal destination first cancels the browsing
  lookup; final UI commits recheck ownership and multi-view stays busy until
  its terminal commit, so delayed completion cannot steal the new destination.
  Reminder receipts check row/token/store revision and accepted
  record; restoration invalidates old cancellation receipts. Undo cancellation
  rechecks current fixture identity/status/time and uses accepted reschedules,
  never the obsolete snapshot. Permission failures retain Settings recovery;
  cancelling a reminder keeps its bookmark. Bookmark stores, sources, transport
  and PiP owners stay unchanged.
- **Evidence**: Approved browser concept; source review and parser checks.
  Independent review caught/fixed loader-canvas overflow and enabled-but-no-op
  Match Center Watch/Retry controls and modal/player presentation conflicts.
  Sequential simulator-free local CI passes:782 tests,780 passed/two optional
  skips, zero failures; unsigned generic-iOS Release compiles. No new warning
  is emitted by the gate. Parser/project-plist/targeted whitespace checks pass;
  owned DerivedData, result bundles and logs are removed (28GiB free afterward).
  The final ownership review finds no concrete stale-publication regression.
  offscreen host layout checks calibrate actual semantic-font expansion instead
  of assuming Catalyst environment changes enlarge text (288pt measured165pt
  in both settings). Those measurements do not qualify phone Dynamic Type.
  No compile/unit result is native visual or physical playback acceptance.
- **Open acceptance**: Actual owner-device comparison to the Inline preview,
  light/dark, narrow iPad landscape, maximum text/long two-match names, VoiceOver
  focus and Cancel/Undo journeys remain a separately authorized gate. This is not
  an installed update or a new shared beta. Relevant Apple guidance:
  [Loading](https://developer.apple.com/design/human-interface-guidelines/loading),
  [Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

## 2026-10-04: Complete121 existing-group internal TestFlight release

- **Authority/outcome**: Finish the owner-authorized internal upload using only
  Fotty Internal Smoke. Existing group attached; UI confirms121 Internal / Testing,
  Saved notes and11 invitations.111/100 remain available; no membership change.
- **Independent evidence**: Apple API13:56:52 AST confirms2.0.1(121), VALID,
  INTERNAL_ONLY, IN_BETA_TESTING, usesNonExemptEncryption=false, external
  NOT_APPLICABLE. Automatic notifications already true, not changed. Group
  availability does not prove email delivery or installed-binary acceptance.
- **Compliance boundary**: The earlier modal is closed and normal group dialog
  appears on this turn's fresh check. Agent submits no declaration this turn;
  how it cleared is not established. Owner confirms all current testers outside
  France and is in Tobago. Stop repeating the country question; no France
  distribution enabled. Source facts remain CryptoKit AES-GCM/HMAC plus locally
  composed PBKDF2; public Apple guidance does not explicitly resolve that KDF
  composition's classification. Do not invent a legal exemption determination.
- **Preservation**: No source edit/build/device action, credential/role change,
  support request, public release, Git publication or backend deployment. Both
  devices remain untouched. Small handoff proof retained; packaging stays cleaned.

## 2026-10-04: Save121 testing notes; await country fact for compliance

- **Evidence**: Owner restores ASC browser sign-in. Build2.0.1(121) English
  (U.K.) What to Test is saved; UI says Saved. No all-provider/PiP/zero-jank or
  downloaded-device acceptance claim. Groups0; Add Group routes to compliance.
- **Remaining fact**: Standard-algorithm questionnaire path asks whether this
  private beta is distributed in France. Source uses OS CryptoKit AES-GCM/HMAC
  and app-composed PBKDF2. Do not guess the country or mislabel PBKDF2 an OS API.
  Owner asked for the geographic distribution fact; no declaration saved.
  Do not claim Testing/group availability until Apple confirms it. This is not
  a confirmed code defect or legal classification. Form stays open for owner.
  No source change/build/device action/tester-role change; saved notes only.

## 2026-10-04: Internal121 upload succeeds after Xcode sign-in

- **Authority**: Owner authorizes internal TestFlight upload only. Keep the
  existing11-person Fotty Internal Smoke group,111/fallback100 and memberships;
  leave both devices untouched, especially the owner-ended iPhone test gate.
- **Evidence**: Native/test/config/qualification support remains identical to
  owner121; only later docs differ. Fresh994-file pre-archive receipt
  `backups/release-source/2.0.1-121-testflight`, source SHA256
  `f1f5fb077c1b1f19c55f17e82e7ab44816a826d09817b4e0eca0b3f22054deae`.
  Official Xcode27/jobs1 optimized archive, strict signatures, blank embedded
  keys, manifests/icons/dSYMs and immediate pre-export source comparisons pass.
  See release121 for archive fingerprints; these are not uploaded-binary proof.
- **Blocker**: Existing internal-only export fails with Failed to Use Accounts.
  Existing API-key retry reports empty role/no distribution signing certificate.
  Native Xcode Apple Accounts is signed out; sign-in window opened for owner.
  Reading TestFlight with the API key is not distribution-signing proof. No new
  credential, permission, tester, backend, Git or FPL change. Build121 is not
  uploaded; Apple still lists111 latest. Owner subsequently restores enrolled
  account; Xcode shows Admin team. Close the GUI before the command-line retry.
  Xcode automatically created a new27.0.1 iPad symbol cache at11:10:30 AST;
  remove only that6.3GiB cache after GUI exit, preserving the September27.0
  cache. First-attempt packaging/logs are removed; receipts stay. Retry requires
  a fresh pre-archive receipt because these documentation updates are later.
- **Recovery**: Signed-in retry uses fresh994-file receipt
  `backups/release-source/2.0.1-121-testflight-signed-in`, source SHA256
  `4148d9b3348c7affdaffe587fba6fb4acec30191ab3a18c430d2ccda1af36912`.
  Independent native-input parity, source/restore comparisons and archive checks
  pass. Xcode reports Upload succeeded / EXPORT SUCCEEDED11:24:36 AST.
  Apple processing and existing-group assignment remain a separate verification
  gate; do not call an uploaded build Testing before that evidence exists.
- **Current external gate**: Apple11:27:26 AST confirms121 VALID/INTERNAL_ONLY,
  ID `e8fffe58-a819-4f79-96b8-be9214b41679`, MISSING_EXPORT_COMPLIANCE/null
  declaration. Existing API key rejects PATCH403, no mutation. ASC browser is
  signed out; owner sign-in page opened. Do not call this tester availability.
  Private backup uses CryptoKit AES-GCM/HMAC but app-composed PBKDF2; do not
  blindly repeat an HTTPS-only declaration or call the KDF an OS API. No legal
  exemption determination/source change made; see release121/Apple guidance.
  Packaging/logs/new device-symbol cache cleaned; approximately33GiB free.

## 2026-10-04: Correct phone Matchday claims and qualify owner121

- **Confirmed defect**: Phone120's neutral raw Villa/Palace Home listing became
  Matchday LIVE and Following Premier League. Decoded iPad footage is women's
  football; elapsed provider timing and bare club names were not that proof.
  121 introduces listedNow grouping/shared card status and rejects roster-only
  league-follow inference. The no-score player header follows the same live
  distinction. Preserve Watch, saved intent and explicit verified evidence.
- **Verification**:761 Catalyst passes/two intentional skips, six new regressions,
  version/catalog/provider checks, sequential unsigned/signed optimized Release,
  strict nested signatures/blank provider keys and frozen compare pass. Exact
  11 native/test/config receipt paths differ from120; no transport, source switch,
  FPL, persistence or qualification-support change. Install command times out but
  app inventory, native Settings121 and normal PID604 launch prove completion.
- **Physical phone**: iPhone15ProMax/iOS27.0.1 Home/Matchday/Settings render and
  navigate; false LIVE/PL-follow entry is gone. Visible preferences remain.
  67.711982s actual navigation trace has no >250ms potential hangs,22 app hitches,
  maximum20.838041ms. Not zero-jank or comparable speedup proof. Two Brighton
  broadcasts decode; Pause holds at81:25. Owner says it runs perfectly and ends
  phone testing: leave it alone, no further device actions. PiP/background/
  restoration/Close were not newly qualified. Concurrent other-app use is not
  Fotty crash/PiP-failure evidence. Audible owner reply is not background proof.
- **Scope and provenance**:993-file pre-build receipt
  `backups/release-source/2.0.1-121-owner-iphone`, recovery commit
  `9cc2d6226370239d2ca6f4e0d8a5d9961e894443`, source SHA256
  `35b75f80039f09f9488c76551cb98cc3750f39bf5a5b9ab56ba2ce1f563fb708`.
  See release121 for signed fingerprints and evidence limits. Existing early
  cached-score header bypass remains a focused caveat outside this repair.
  Keep iPad120 proof separate. Shared111/fallback100 unchanged; distribution
  archive/export/upload needs its separate gate. Owner121 is a candidate for the
  next existing-group internal beta, not an uploaded/processed shared build.
  Removed only245MiB owned trace/export/launch output after compact review;
  34GiB free. Build outputs had already been cleaned automatically. Receipts and
  unrelated data remain; no phone action follows the owner's stop.

## 2026-10-04: Finish owner120 iPad navigation and Watch Two performance gate

- **Measured cause and repair**: Follow-up117–119 recordings narrowed repeated
  Home/CPL work to clock-invalidated immutable facts, date parsing, Matchday
  matching and multi-view admission.120 prepares selection once per projection,
  checks supported sources first and uses one early-stop candidate pass, and
  memoizes exact short ISO8601 inputs under the existing formatter lock.
  Preserve full selection/revision invalidation and all current time-relative
  freshness/phase/eligibility guards. Cache pure results, not accepted snapshots.
  NSCache retention limits are advisory; eviction never changes parse behavior.
- **Verification**:755 Catalyst passes/two intentional skips; seven new semantic
  regressions plus version/catalog/provider checks pass. Sequential unsigned/
  signed optimized Release, strict nested signatures and blank embedded keys
  pass. Exact Jet iPad in-place install/normal launch/visible120 pass. Typed
  local preferences including the manager ID remain; SwiftData not compared.
- **Actual native evidence**: Two installed120/PID3171 navigation recordings
  last45.865955s/45.714625s. Neither reports a >250ms potential hang; 37/25 app
  hitches remain, maximum99.994416/49.995ms. Do not call this zero-jank or infer
  a speedup percentage from changing live catalogs/workloads. Real Home dragging
  and repeated Home/Matchday/Settings navigation render and recover normally.
- **Watch Two**: Two football broadcasts decode/advance together. Independent
  source selection, paused-other-pane preservation, per-pane Pause/Play, Swap,
  Equal/Focus, Fit/Fill and Close pass. Focus labels fit. Source clock offsets
  and brief layout reloads remain. Visual audio focus is not audible audio/
  teardown qualification; PiP/background/iPhone are separate. Villa footage is
  women's football, not proof of a men's PL fixture/cohort. See release120.
- **Provenance and scope**:992-file pre-build receipt
  `backups/release-source/2.0.1-120-owner-ipad`, recovery commit
  `361f0f94f8dd77faaa5a659db8d7dca0c3cc389b`, source SHA256
  `427d65b0aabc25f5e63b12d598b8dd127a31165e193a6857566d9d20b7d12cd6`.
  Secret scan/restore/pre-install compare pass; documentation is later.
  Apple UI/staged performance guidance informed native checks and evidence
  limits. Owned temporary artifacts are cleaned after compact results; immutable
  receipts and unrelated data stay. Shared111/fallback100 unchanged. No FPL
  features, TestFlight, Git publication, backend, tester or spending change.

## 2026-10-03: Measure Home stalls, repair repeated work and install owner116

- **Evidence**: Exact installed115/Jet iPad SwiftUI trace45.933s found13 Home
  body updates/2.181s total/max214.526ms overlapping four main-thread hangs
  (max1.352s). This is real runtime evidence, not delayed mirror capture.
  No matched115 symbols or successful mirrored-scroll workload; individual
  function self-cost and scroll qualification are not established.
- **Repair**: Prepare immutable follow/league selection once; revision-key
  same-count interest edits and publish per-event follow/major-league facts with
  discovery. Raw arbitrary events bypass ID-only facts; inactive filters short
  circuit. Preserve fixture matching/ranking/source eligibility/persistence.
  Physical115 also exposed fragmented Source1 in the Focus sidebar. Compact
  persistent chrome now separates identity/controls, retains scaled44pt targets,
  single-line source labels, allocated width and16:9 fitted video. Apple UI and
  staged performance-audit guidance shaped these focused repairs, not a redesign.
- **Verification**:736 Catalyst passes/two skips; nine new regressions; old
  source-shape contract corrected and full suite rerun. Seven version tests,
  provider/catalog identity, unsigned/signed optimized Release, strict signatures
  and empty embedded keys pass. Only Jet iPad received2.0.1(116); normal PID2474
  remains present. Exact typed preference comparisons preserve local manager,
  season, interest filter, reminders, appearance and review payloads without
  publishing IDs. SwiftData follows were not separately compared.
- **Provenance**: Final988-file pre-build receipt is
  `backups/release-source/2.0.1-116-owner-ipad-r2`, recovery commit
  `fe6b7691cb1c0c0492aceb5a6b0f265dffe7a4c0`, source SHA256
  `1a0dd10bf92c9b15818b8e2bac9c1e706aabc77f011557deb631acb045ea120a`.
  Secret scan/restore/pre-install compare pass. See release116 for executable
  and bundle fingerprints; later documentation is not frozen build input.
- **Active blocker**: Mac locked; automatic unlock fails. iPad is connected and
  unlocked. CLI app/PID attachment fails even with official Xcode pinned, while
  installed get-task-allow is true; do not infer an entitlement restriction.
  Earlier GUI115 recording worked. Unlock Mac, rerun the same116 workload and
  inspect compact Focus controls. No measured improvement/native116 visual or
  shared-release qualification claimed; approval for this repair/device gate
  remains active and does not need repeating.
- **Resources**: Correct packaging PATH/tool discovery before heavy work; keep
  a checked app until install rather than let optional diagnostics force rebuilds.
  Sequential jobs1/no simulators; owned outputs cleaned,43GiB free. Retain only
  matched43MiB dSYM in `backups/performance/owner-2.0.1-116` for pending profiling,
  then remove. No TestFlight/Git/backend/tester/spending/FPL feature change.

## 2026-10-03: Continue approved repairs without repeated permission and install owner115

- **Authority**: The owner explicitly clarified that known repairs and the
  already-approved named-device testing gate should continue without repeat
  approval; major new scope/UX/architecture, privacy/security, cost or distribution
  decisions still need direction. AGENTS/Workflow now preserve that distinction.
  Only Jet iPad was targeted; no iPhone, TestFlight, Git publication, backend,
  tester, spending or FPL feature change.
- **Identity**: Source/app/extension advance together to2.0.1(115). Seven offline
  version tests/preflight pass; no functional change follows the727-pass/two-skip
  Catalyst and unsigned iOS gate. Signed optimized Release, strict nested
  signatures, empty embedded provider keys and installed CoreDevice115 identity
  pass using official Xcode27 and jobs1.
- **Receipt**: Pre-build987-file capture, default secret scan/round-trip restore
  and pre-install compare pass. Recovery commit
  `11c4e158463fad38c061e65a027aebc37c1eb226`; source SHA256
  `85d899ea6b32db2af3d840703282faef041a6d09ee925931b0e05fb2a9a3e661`.
  Independent review confirms212 captured native inputs still match. Later
  documentation is outside this frozen source receipt. See release115 for the
  distinct recovery-bundle and locally signed executable fingerprints.
- **Physical evidence**: Home/Light/landscape shows neutral Broadcast listed
  and More events. Hockey Watch reaches sport-specific loading; Pause/Sources
  labels fit on one line. No successful source-switch, decoding or PiP check is
  claimed. Mac lock briefly blocked control; access returned but Device Hub
  reports AVC stream RTCP timeout/CoreDevice9015 on localNetwork. Restarting
  screen sharing did not stabilize it, and iPad Home remained unobservable.
  This is a control-transport failure, not app-crash/provider-failure evidence.
  The same app process remains present beyond60 seconds. Normal app termination/
  relaunch retires the agent's test attempt; no data reset. Stable cable/control
  access is the next physical prerequisite, not another approval request.
- **Data limits**: Baseline preferences copied before install, but plutil's
  whole-plist JSON conversion failed on typed objects. Automatic cleanup removed
  the copies, so exact equality cannot be reconstructed. Subsequent typed read
  confirms positive local manager/season, interest preference and reminders
  presence without displaying IDs. Saved payload is absent with no established
  prior payload; follow records were not compared. No blanket preservation claim.
- **Cleanup**: Local packaging-path/search-path errors were repaired without
  bypassing signatures or source/secret checks. Each failed/interrupted and final
  gate automatically removed owned build/DerivedData/log/preference output;
  subsequent inspection copies are also removed.46 GiB free; intentional source
  receipts and unrelated user caches remain. No simulator or UI-test runner.

## 2026-10-03: Resolve confirmed owner-iPad toolbar, listed-status and web-attempt recovery defects

- **Authority**: Owner requested resolving the reported findings, not merely
  explaining them. Source/local verification only; no new build number, signing,
  installation, TestFlight, Git publication, backend change or FPL feature work.
  Frozen owner114 and shared111 remain unchanged.
- **Physical evidence**: After retry, normal Device Hub control worked on Jet
  iPad114. Home/Matchday/Settings, Light/Dark restored to Light, provider fullscreen
  Pause/Play, advancing WebKit PiP outside Fotty for more60 seconds, restoration
  and the six-choice Sources sheet worked. The decoded baseball video was an
  end-card loop. Sources wrapped; second-source black playback/control state was
  not proven because capture lag and auto-hidden chrome limited observation.
  No crash, actual live-match decoding, scroll timing or successful second-source
  recovery is claimed. Two Instruments attaches did not find the app process.
- **Truthful status**: Raw provider coverage retained the same baseball names and
  kickoff as a fresh official finished fixture, but lacked required competition/
  cohort identity. Do not loosen the merge or suppress rows by names/time alone.
  Neutral "Broadcast listed"/listed counts replace false red ON NOW claims;
  confirmed LIVE/counts retain verified status. Fresh official terminal rows
  remain filtered; Watch/source eligibility and source admission are unchanged.
- **Native layout**: Measure the real UIKit Pause/Sources labels and symbols,
  honor scaled text and44-point targets, and reflow when width is insufficient.
  Hidden Sources deactivates only its minimum constraints, avoiding a stack-view
  zero-size conflict. No new overlay gesture or duplicate provider control.
- **Lifecycle**: Both single and two-match web surfaces use attempt-keyed
  WebViews. Pause/audio/rotation/scene changes retain identity; selected source/
  retry replaces it. Attempt-tagged bridge messages and committed URL/query/
  navigation ownership reject stale events. First selected-load commit gates
  unknown navigation starts. Native startup deadlines cover missing JavaScript;
  navigation/process failures recover only the current attempt, with explicit
  pause/background cancellation. PiP resets on document replacement and stale
  source/attempt callbacks cannot clear the new player's state. Teardown
  invalidates work, recursively suspends child media, invokes native WebKit
  pause/close and releases delegates. Allowlists/cookie-domain boundaries remain.
- **Verification**: Independent scoped review and Swift parse/whitespace checks
  pass. Added UIKit geometry, executed-JavaScript, navigation ordering, native
  teardown and PiP regressions. Final tools/ios-ci.sh passes sequential jobs1,
  official Xcode27 and no simulator: structured Catalyst result is727 passed/two
  opt-in skips/zero failures, including the18 new regressions; unsigned generic
  iOS Release passes. Coherent version and five provider identity vectors pass.
  The installed
  114 receipt does not capture this modified source. Six Mac audio activation
  warnings remain; no new mobile performance diagnosis is implied.
  Initial qualification corrected test-helper visibility and invalid manual
  WKNavigation fixtures: verified host crashes were CFRetain(NULL) in WebKit
  navigation deallocation. Real offline HTML navigation objects replace those
  fixtures without weakening production ownership checks; final tests pass.
  Apple UI guidance informed label sizing/reflow and honest status presentation;
  tests/builds are not a native screenshot or owner acceptance.
- **Next gate**: Separate owner-device authority, new immutable source receipt/
  build identity and exact-source switch/retry/PiP/no-duplicate-audio acceptance.
  No old Mac app or browser preview qualifies the repaired native UI.
- **Cleanup**: Owned build/DerivedData/results/logs were removed on every exit.
  Five positively identified invalid-fixture host crash reports were summarized
  and removed; unrelated logs/caches and the intentional owner114 source backup
  are preserved.47 GiB remains free. No binaries or screenshots retained.

## 2026-10-03: Install private usability build114 on Jet iPad without claiming interaction acceptance

- **Authority**: Owner approved proceeding from the native qualification gate
  to exact-device checks. Jet iPad was the only available owner device; Jelani's
  iPhone remained unavailable and no substitute phone was targeted. No TestFlight,
  development-repository commit/push, backend or FPL feature change.
- **Identity**: Allocate2.0.1(114) across app/widget/source configuration to avoid
  confusing the current repairs with frozen candidate113. Seven offline version
  regressions and coherent-version preflight pass. No functional code changed
  after the709-test/two-skip current-source gate; only version metadata changed.
- **Provenance**: Verified pre-build local receipt has986 files, recovery commit
  `b94ffa258118519b4c532f9bfe3d7c5d0a1f24f9`, source SHA256
  `7a7272026ba8d7b56b888773950e74ba1bb5e24e54716b8db161594a45937ddb`.
  Full secret scan/round-trip restore and pre-install compare pass. It captures
  this dirty working tree, not the narrower frozen113 assembly; it is not an
  off-Mac backup or a backend deployment receipt.
- **Physical checks**: Official Xcode27/27A266a, sequential jobs1, signed optimized
  Release and strict nested signatures pass. CoreDevice reports installed114 on
  Jet iPad Air4/iPadOS27.0.1; normal Fotty process survives a60-second relaunch hold.
  No matching Fotty crash files were found before/after. This proves identity and
  sampled process survival, not rendered responsiveness, scrolling or media.
- **Local data**: A bounded post-install preference read confirms a positive
  local manager, matching confirmation/current season and a present disabled
  Home-interest filter. No manager value was printed, embedded or exported.
  A planned baseline read arrived after installation and cannot establish a
  pre/post comparison; saved-match payload was unavailable in this read. Follow
  records and full retained-state/backup acceptance remain open. No preferences
  were changed and no app data was wiped/restored.
- **Interaction blocker**: Owner screenshot shows Computer Use/Any App enabled.
  This chat's tool still denies Device Hub and, after reset, exposes no native
  app surface; do not ask for broader permissions or bypass it with shell/HID,
  preference writes or an iOS UI-test runner. No UI, live playback, PiP or
  performance acceptance is claimed. The Apple UI/performance workflows keep
  those evidence levels distinct; six Catalyst audio warnings remain unqualified
  on the device.
- **Cleanup**: Owned signed app/DerivedData and transient private preference
  copies are removed. A copy completing alongside cleanup recreated a308-KiB
  owned folder; root explicitly removed and reverified it after transfers stopped.
  Retain only the intentional19-MiB source receipt;46 GiB free. See release114.

## 2026-10-03: Qualify current usability repairs after full-access restoration

- **Scope**: Owner enabled full access and requested retrying the blocked native
  checks. Source/local qualification only; no install, signing/archive, TestFlight,
  commit/push, deployment, spending change, FPL feature work or skill activation.
- **Environment**: Official Xcode27/27A266a now compiles the Swift macros normally.
  The first full-access attempt compiled but stalled in a header-only badge test;
  this was a test-fixture failure, not an observed app crash.
- **Focused repair**: Add explicit MIME/nosniff metadata to the controlled
  URLProtocol fixture, bounded session deadlines and a fail-only watchdog. Cancel
  that watchdog before waiting for transport shutdown and assert it never supplied
  cancellation. Keep the fixture body-free with no successful completion callback;
  both tests still exercise the actual production downloader and task cancellation.
  Independent review passes. No app transport code changed in this follow-up.
- **Evidence boundary**: This verifies the controlled fixture on the tested
  Foundation runtime and the collector's two-MiB application accumulation limit.
  A bounded real-wire header-only probe did not establish prompt header admission;
  do not claim a universal transport timing or Foundation-internal buffering bound.
  Existing production request/resource timeouts remain8/12 seconds.
- **Verification**: Final full tools/ios-ci.sh gate passes, sequential jobs1/no
  simulator. Structured xcresult reports709 passed, two intentional opt-in skips,
  zero failures; unsigned generic iOS Release passes. The nine focused suites
  executed, including terminal/reminder queue, saved cricket, CPL cancellation,
  Home replacement, backup fencing, badge cancellation and native/Watch Two retry
  regressions. Skips are the opt-in reference HLS soak and live Score808 discovery.
  Five provider identity vectors and coherent2.0.1(113) version preflight pass.
- **Open evidence**: Six SessionCore_macOS_Legacy audio activation warnings were
  recorded in the Catalyst test host. They are not mobile smoothness proof or a
  demonstrated iOS defect; exact-device performance and playback/PiP/Watch Two,
  retained data, reminder delivery, backup and accessibility acceptance remain open.
  This current working tree is not the frozen Oct1 candidate113 receipt; shared111
  and owner112 are unchanged. No new distribution receipt/build number allocated.
- **Cleanup**: Owned CI output, result bundles, compiled probes and module caches
  were removed after both failure and success.47 GiB remains free; unrelated user
  artifacts and caches were preserved.

## 2026-10-03: Close verified terminal precedence and queued reminder edge cases

- **Scope**: Follow-up local qualification of the approved usability repairs;
  FPL feature work remains paused. No install, upload, publication, deployment,
  commit, spending change or new build number.
- **Confirmed failures**: A separate lagging score poll could keep an accepted
  finished/cancelled fixture Live or preserve a future cancelled countdown.
  Reminder reconciliation captured records before an earlier queued opt-in
  finished its permission/add wait, missing a new record and its bookmark.
- **Repair**: Only verified terminal fixture facts outrank nonterminal score
  states. Genuine live, unverified/nonterminal ordering and raw final score labels
  remain unchanged. Derive reminder evidence after the previous queued operation
  completes; apply accepted terminal facts to its newly created bookmark before
  revoking the alert. Missing or conflicting fixture evidence cannot cancel it.
- **Verification**: Independent bounded reviews pass. All five follow-up Swift
  source/test files parse and whitespace checks pass. Added native regressions
  cover lagging score states, permission/add suspension, retained terminal
  bookmarks and missing/conflicting controls; they remain unexecuted. An isolated
  harness compiled the actual production queue method against controlled model
  doubles and passed four cases, not the app suite or physical acceptance.
- **Remaining gate**: A minimal SwiftUI compile probe reproduces the same sandbox
  macro-launcher failure before Fotty code is involved. Full native qualification
  remains blocked; do not bypass it or reuse frozen Oct1 candidate113's receipt.
  Run tools/ios-ci.sh in normal macOS Terminal, then obtain separate exact-device
  authority/acceptance. Owned probe/harness output was removed;47 GiB free.

## 2026-10-03: Repair confirmed app-wide usability and lifecycle defects locally

- **Scope**: Owner approved all confirmed audit repairs, focused on usability
  and performance. FPL feature work remains paused. Source/local verification
  only: no install, TestFlight, commit, push, Worker deployment or spending change.
- **Playback**: Explicit native Pause revokes recovery permission, including
  network restoration and stall callbacks; explicit Play renews it. Preserve
  native/WebKit PiP ownership and background suspension semantics. Watch Two's
  delayed retry now has source/attempt/token ownership and cancellation fences;
  stale, recovered, paused or dismissed attempts cannot reload a panel. Goal
  Audio only focuses a viable panel, preserving working audio on a failed slot.
- **Saved state and fixtures**: Verified finished/cancelled facts reconcile saved
  matches and reminder revocation without re-entering playable catalogs. Persist
  cricket status/format/receipt metadata compatibly, retain exact-team artwork,
  and invalidate Matchday projections on same-count content changes. Source-free
  elapsed CPL starts await confirmation rather than inventing Live; valid untyped
  provider Live behavior stays unchanged. Unavailable cricket cohorts retry after
  five minutes. Cancelled CPL checks release their throttle; normal checks retain
  the reviewed thirty-minute cadence. Missing fixtures never imply cancellation.
- **UI, recovery and resources**: Revalidate Home selection when actual sports
  change, not just row count. Watch accessibility labels name the event/channel;
  section titles expose heading semantics. Backup review generation tickets fence
  stale success/error/busy publication after input changes or dismissal. Badge
  refresh replaces old remote URLs deterministically, preserves current concurrent
  lookup results and deliberate artwork overrides, and validates URLs before
  counting success. Streaming collection rejects oversized headers before reading
  and stops unknown/lying-length bodies at the existing two-MiB boundary; cancel
  the transport without changing coalescing, bounded cache or thumbnail decoding.
- **Verification**: Independent scoped reviews and whitespace checks pass; all
  23 edited Swift source/test files parse. Seven offline native-version tests and
  five provider identity vectors pass. A temporary Foundation-only harness compiled
  actual production badge/retry/audio helpers and passed 17 assertions; it is not
  the app unit suite, a device test or measured smoothness evidence. Added focused
  native regressions remain unexecuted: the full simulator-free gate failed at
  Catalyst compilation because the session sandbox rejected Swift's macro-plugin
  launcher (`sandbox_apply: Operation not permitted`). Do not bypass that boundary
  or report a qualified build. Run `tools/ios-ci.sh` in an authorized environment,
  then request separate exact-device playback/PiP/Watch Two, backup and accessibility
  acceptance. No simulator was launched. Owned CI/harness output removed;47 GiB free.
- **Receipt boundary**: Source still identifies 2.0.1 (113), but these repairs
  postdate the frozen Oct1 candidate113 and invalidate reuse of its qualification
  receipt for this working tree. Shared111 and owner112 are unchanged; no new
  build number or distribution receipt was allocated. Current remote health was
  not probed by this source-only repair gate.

## 2026-10-03: Prepare reusable iOS design and performance skill upgrades

- **Scope**: Owner chose reusable iOS skills, not Fotty-only guidance. Current
  focus is usability/performance; this instruction-maintenance gate authorizes
  no app/FPL/backend changes, builds, device actions, publication or release.
- **Decision**: Preserve the existing Apple UI skill and add a native-reference
  handoff; pair it with an evidence-led iOS performance audit. Keep portable
  packages in `agent/skill-candidates`, synthetic trials in `agent/skill-evals`
  and Fotty-specific tool/ownership routing in `agent/playbooks/ios-skills.md`.
  Root AGENTS and Current-State link that adapter. Personal installed skills
  remain unchanged/read-only; global activation is a separate pending gate.
- **Verification**: Both skill manifests validate, YAML metadata parses, five
  local reference links and all eight fixture cases resolve. One independent
  evaluator passes eight reviewer-graded behavioral cases, including first-load
  cache loss, same-ID stale scores, leaving correct code unchanged and rejecting
  unsupported/confounded performance claims. Synthetic trials are not app proof.
  Independent source review found and reverified fixes for an ignored fixture
  and missing routing. No dependency install or temporary build output.
- **Evidence**: `docs/audit/Fotty-iOS-Skill-Upgrade-2026-10-03.md`. Future global
  activation needs permitted personal-directory access and a fresh comparison;
  do not bypass the boundary or treat staging as automatic discovery.

## 2026-10-01: Qualify coherent native candidate113 without distributing it

- **Scope**: Owner approved proceeding with overall reliability priorities.
  First gate is source-only candidate preparation/qualification, not a device
  install, TestFlight release, development-repository commit/push or deployment.
  Shared111 and owner iPad112 remain unchanged; the seven-day round is unstarted.
- **Confirmed repair**: A fresh CPL receipt was awaited but ignored by the
  older-provider early return. Accept the schedule before that guard, project
  source-free CPL rows and include them in saved/reminder reconciliation. Keep
  unrelated rows/sources and older/unverified snapshot rejection. Two parameterized
  regressions cover kickoff changes in both directions and rejected revisions.
  Controlled tests prove identity resolution, not real notification delivery.
- **Candidate isolation**: Restore verified owner112; overlay exactly ten native/
  config/test paths and three gate-tool paths. All228 native/gate inputs byte/mode
  match primary; no native additions/deletions. Preserve unrelated dirty work.
  Retain older baseline web files; separately record deployed PR36 source/version.
  The native snapshot is not a substitute backend deployment tree.
- **Reproducibility**: Pre-build local receipt has964 files, one independent root
  commit `70e32ca0cecafcfad6aa8482767fce882dbbfb92`, source SHA256
  `d94562b4df02b756e3797fc341524a92c64a33924eea1d8963ffab1690e4d87c`.
  Full secret scan, round-trip restore and post-build comparison pass. A failed
  mechanical overlay was corrected before building; review then caught malformed
  YAML introduced by version allocation. Correct it and add parsed app/extension/
  four-configuration version preflight plus seven offline tests; recapture and
  rerun the full gate. Neither rejected receipt is the final candidate.
- **Qualification**: Official Xcode27/27A266a, sequential jobs1/no simulator:
  657 Catalyst tests passed/two opt-in skips/zero failures, unsigned iOS Release
  passed; five identity vectors, 13 recovery and seven version tests pass.
  Four existing Mac audio activation warnings remain explicit, not a mobile
  performance defect claim. Fresh20:57 UTC production health identifies source
  `2026-10-01.cricket-corrections-1`; verified cricket67/sports70 retain the three
  reviewed ICC starts. No paid or live-score probe was made.
- **Next gates**: Release113 and build113 ledger replace stale current routing,
  preserving historical93 evidence. Exact phone/tablet launch and retained data,
  sustained playback/PiP/Watch Two, actual reminder return, disposable Files
  recovery, accessibility and one independently received report remain open.
  Current19 MiB receipt stays local; newest verified off-Mac backup is still93.
  Owned assembly, rejected receipts, logs/DerivedData/results removed;44 GiB free.

## 2026-10-01: Publish and deploy only the verified ICC correction ledger

- **Authority/scope**: Owner explicitly approved protected publication and
  Worker deployment. Native changes, installs, TestFlight, new sources, accounts,
  secrets, spending and paid-Coach settings excluded. The clean attached
  checkout isolates three functional files, unique identity and operations doc;
  unrelated dirty primary work and differing package/lockfile are preserved.
- **Protected receipt**: [PR36](https://github.com/jetboss/Fotty/pull/36) passed
  Web CI36915867915 (including optimized build), quality36915868048 and
  CodeQL36915867920 before normal squash merge
  `0416690f66019657dea4c299d51546b5b3b3c7a6`. Exact candidate tree equals
  that merge; the reused release checkout is clean/detached there.
- **Qualification**: Exact clean lock, bundled Node24:326/326 units, typecheck,
  focused zero-warning lint, dry-run, staged/source gitleaks and whitespace pass.
  Baseline full lint remains48 warnings/zero errors. Independent backend/native
  review finds no contract blocker. Existing ten dependency alerts remain open;
  reachability triage finds no Worker-runtime blocker, not zero vulnerabilities.
- **Deployment**: Source `2026-10-01.cricket-corrections-1`, Worker version
  `87b347ed-0b0c-4df1-b0ec-9c755f06fc5d`, deployment
  `dfe83ec8-61e8-4fc2-b5ba-73367a120c54`,100% traffic. Runtime/migration,
  four DO namespaces, rate limits, vars and four secret names/types compare
  exactly with source4. Cron remains five minutes. Exact-version scheduled
  invocation at19:46:01.790 UTC is ok/zero exceptions; tail stopped.
- **Recovery**: At19:46:20 UTC all67 IDs remain, only the three reviewed starts
  change, other64 starts stay equal. WI9/ICC58 receipts19:45:36.647 UTC;
  source verified, aggregate/per-cohort failures0, no internal evidence leaks.
  Hosted cricket36916807008, sports36916809058 and CPL36916811364 all pass on
  merged main. CPL reports schedule current without fixture commit/PR.
  CWI current/next24h audit is healthy; sports remains same-publisher comparison.
  Health/embed, CPL39 and complete3/3 catalog pass; no paid-Coach/live-score call.
  Reviewed incident34 closed; failures before recovery stay historical evidence.
- **Boundaries/cleanup**: No app build/install/release. Owner112 already accepts
  same-ID correction/cache/reminder reconciliation, but the replay-refresh
  repair remains local; shared111 predates broad cricket ingestion. Physical
  delivery is not proved. Owned dependency/bundle outputs removed,44 GiB free.
  Rollback is code-only to source4/versiond1cdb4e4; never reset accepted data.
  [Full deployment receipt](https://github.com/jetboss/Fotty/pull/36#issuecomment-5939284827).

## 2026-10-01: Admit three verified ICC kickoff corrections and fix cricket replay refresh locally

- **Authority**: Owner approved the focused fixes after source verification.
  Source-only implementation/qualification; no commit, publication, deployment,
  installation, TestFlight, credential or spending change.
- **Verified facts**: Rendered ICC women fixtures and canonical match-centre
  pages confirm275298 Oct4 02:00Z,275299 Oct6 02:30Z,275300 Oct7 02:00Z.
  The complete18:38:42 UTC feed agrees in UTC/Malaysia/India, but its revision
  flags are false. This is authoritative ICC publication, not independent-board
  corroboration. The initial slugless-page reads were not clearance; rendered
  canonical links resolve the publication evidence. See cricket operations.
- **Repair**: Immutable `icc-kickoff-corrections.mjs` authorizes only these exact
  retained-old→collected-new scheduled transitions, requiring real ordered
  women/team identities and names, series15827/name, T20/ICC scope, canonical
  source, equal row/collection receipt after verification, ≤6h age and expiry
  before either kickoff. It never rewrites a source row or fabricates
  `is_revised`; internal series evidence is stripped before publication.
  Unknown unflagged moves/reversals still reject. Subsequent explicitly revised
  publisher corrections retain existing authority; this is not permanent time
  pinning. Complete collection, cohort isolation, watermark/terminal guards,
  durable persistence, retry budgets and CPL ownership are unchanged.
- **Native**: A replayed provider receipt now merges independently accepted
  cricket with empty provider evidence before returning; cricket/sports merges
  share one bookmark/reminder reconciliation. No stale source is borrowed.
  Three regressions cover±30min changes, exact saved-ID continuity, matching
  stale source exclusion, participant rejection and complete-empty replacement.
- **Verification**: Backend/monitor68, full local web/Worker322, Catalyst655
  passed/two skipped; generic unsigned iOS Release, nonincremental typecheck,
  focused zero-warning ESLint and Worker dry-run pass. Independent source/native
  reviews find no blocking defect. Four existing Catalyst audio-session runtime
  warnings are not resolved by this fixture repair. No simulator used.
- **Live rehearsal**: At19:02:16 UTC, production67 plus fresh complete ICC67
  recovers in memory to verified/zero from43 failures, changing exactly the
  three starts, preserving WI9/ICC58. No cloud write: source4 still holds the
  incident; shared111/owner112 and physical acceptance remain unchanged.
- **Cleanup/next gate**: Owned build/result/dry-run files removed;44 GiB free,
  user artifacts/dependencies preserved. Protected publication and new Worker
  identity/fresh recovery receipts require separate approval; native installs
  and significant shared batches remain separate gates.

## 2026-10-01: Publish and deploy the qualified fixture expansion, without an app release

- **Authority**: Owner answered option 1: publish/deploy verified backend only.
  No new feed/account/contact, spending, paid-Coach/secret changes, native
  publication, device install or TestFlight release. Source strategy for the
  remaining 23 lanes is still a separate decision.
- **Protected receipt**: Reused the clean attached activation checkout; copied
  only nine qualified fixture Worker files and three operations docs. Protected
  [PR35](https://github.com/jetboss/Fotty/pull/35) merged normally, without bypass,
  as `3742b96f08d02e4dce722073f818c3b3f7a4a43d`. All checks pass: Web CI
  36883227752, quality 36883227772, CodeQL 36883227802. The deployed checkout was
  detached at this exact merge. Unrelated dirty primary/native work is preserved.
- **Qualification**: Bundled Node24, exact clean lock; all 321 units, nonincremental
  typecheck, focused zero-warning ESLint, dry-run and redacted scans pass. Full
  repository lint has 48 baseline warnings, zero errors; hosted CI includes build.
  No local app/simulator build. Independent source/consumer review finds no new
  contract regression. Dependency reachability review finds no fixture-runtime
  blocker; existing alert/upgrade PRs stay separate, not silently dismissed.
- **Deployment**: Source `2026-10-01.sports-fixtures-4`, Worker
  `d1cdb4e4-abb5-48a5-b024-2b276ddc23c8`, 100% traffic, registered five-minute
  cron. Existing bindings/website0/WNBA0, Coach disabled/50 and four secret
  names/types remain unchanged. Exact-version scheduled handler observed at
  15:30:45 UTC, outcome ok, zero exceptions; bounded redacted tail ends.
- **Live coverage**: All six football scopes have accepted 15:25:46 UTC receipts
  (empty this window); MLB13/NHL57 give 70 fixtures. Eight covered /23 unsupported
  lanes. Hosted sports monitor 36884399877 passes on merged main; this manual
  dispatch does not prove hourly GitHub scheduler timing or independent league
  completeness. Full all-sport fixture coverage is not claimed.
- **Cricket**: WI9 now refreshes independently; all 58 ICC records compare equal
  to the pre-deploy snapshot and retain 13:00:46 source observations. Three
  unflagged tri-series kickoff changes stay unresolved. At 15:25 the aggregate/
  ICC failure streak is 18, WI0. Monitor 36884670580 correctly still fails
  repeated-sync-failure/coverage-unavailable; partial WI recovery is not healthy
  ICC. CPL39, health/embed and complete 3/3 catalog contracts pass; no paid Coach
  or quota-consuming football-live call. No new physical acceptance claimed.
- **Next gates**: Choose free-only vs paid-source evaluation for 23 gaps; verify
  ICC timing with independent source evidence. Local native valid-empty/cooldown
  fixes still need separate owner-device acceptance before a significant shared
  batch. Operations/source ledger and current summary now reflect source4.

## 2026-10-01: Expand fixture supervision and qualify existing-source coverage without claiming universal data

- **Authority**: Continue the app-wide fixture implementation to its local gate.
  No new commit/merge/publication, activation, install, TestFlight, account,
  publisher contact or spending authority. These remain separate decisions.
- **Coverage**: Reuse the existing football-data credential and one six-code
  bulk query for PL/CL, La Liga, Serie A, Bundesliga and Ligue 1. Remove four
  duplicate gated descriptors; the local manifest has26 groups /31 scopes,
  24 bounded adapters, eight eligible scopes /23 unresolved source lanes.
  Production source3 still covers four scopes, not eight. Existing website/WNBA
  flags and paid Coach disabled/50 policy remain unchanged. Scope migration
  cannot upgrade old PL/CL receipts into healthy empty new leagues; persisted
  attempted scope prevents failed migration from bypassing five-minute backoff.
- **Evidence boundaries**: The six-code account check returns200 with exact
  scope/window/count0, proving transport/schema. Official published PL/UCL
  calendars corroborate expected emptiness for Oct1–Oct8 exclusive, but dynamic
  rearrangements and the other four leagues are not independently certified.
  Required Football-Data.org attribution is included in native/web source.
- **Native repair**: Owner112's legacy football warning has concrete empty-result
  premium and keyless proxy-cooldown paths. Cache valid-empty schedules as
  success, avoid unconfigured fanout, preserve actual proxy/cancellation errors
  and decode before cache admission. Eight injected-session/repository tests
  pass; the exact old device error and new-device acceptance remain open.
- **Cricket incident**: At14:10 UTC production holds67 fixtures (WI9/ICC58),
  eight failures and its original13:00 UTC observation. Fresh ICC changes only
  three future women's tri-series kickoffs by30 minutes with is_revised=false;
  no independent correction clearance. Fresh CWI agrees with all five in-window
  WI fixtures and shows no live/next24h omission. Scheduled monitor36877207360
  confirms repeated-sync-failure/coverage-unavailable at14:33 UTC.
- **Isolation repair**: After the unchanged bounded whole-collection gate,
  independently admit WI/ICC cohorts. Conflicted rows and receipts remain exact;
  cross-cohort IDs, older empty/pending-only receipts and status/time/participant
  guard violations reject. Aggregate failures and five-minute retry persist
  until full recovery. Retained/fresh/CPL unions cannot exceed400: otherwise
  keep the entire previous valid snapshot, not truncated or invalid output.
  CPL authority and admission policy are unchanged. This is source-only, not
  deployment recovery or permission to accept the three disputed times.
- **Supervision**: Updated the existing heartbeat in place using the OpenAI Docs
  workflow: Fotty all-sport fixture supervision, same stable ID/six-hour cadence.
  Both bounded audits and published monitors are checked; admitted scopes,
  deferred gaps and offseason are distinguished. Read-only task-scoped agent
  investigations do not become routine collectors or deploy themselves.
- **Sources still needed**: The per-competition access ledger records all23
  gaps and free F1/AFL candidates with unresolved licence/operator/completeness
  gates. Bounded official paid-provider research favors evaluating TheSportsDB
  first, not buying or claiming universal coverage. Owner must choose a source
  strategy/budget before account/contract/sample activation work.
- **Verification**: All317 backend tests pass, including actual-workerd source
  contracts and63 cricket/monitor tests. TypeScript, zero-warning focused ESLint,
  dry-run and redacted targeted scans pass. Fresh sequential simulator-free
  native gate:652 passed /two skipped; unsigned iOS Release compile passes.
  Existing SwiftLint length/style errors remain, not a zero-warning claim.
  Owned Xcode/runtime/dry-run output is removed;46GiB free, user caches retained.
  No old installed Mac binary substitutes for evidence. Operations details:
  `docs/operations/Sports-Fixture-Service.md`, `Cricket-Fixture-Service.md` and
  `Sports-Fixture-Source-Gaps.md`.

## 2026-10-01: Activate only verified cloud fixture sources and qualify the owner consumer separately

- **Authority**: Owner approved cleared cloud activation and subsequent Jet iPad
  testing. No TestFlight, paid-limit/secret change, public web deployment or
  unreviewed source activation.
- **Publication**: Protected PR31–33 pass full CI/CodeQL/repository gates. PR33
  merged as `7eb401cf00dd06331f4ec5991c989f3c3377b0f2`; deployed source
  `2026-10-01.sports-fixtures-3`, Worker
  `dc563c36-0137-41d5-b2bf-d292634902e7`, preserves existing bindings/budgets and
  registers the five-minute due-check cron.
- **Production correction**: Node mocks missed workerd's unsupported
  redirect:error. Both collectors now use manual and reject 3xx without following
  Location. Real edge-runtime regressions cover success, redirects and source
  gates; diagnostic receipts contain finite stage/code/kind/status only.
- **Cleared scope**: PL/CL credentialed scope/window/count checks and successful
  production receipts pass; MLB13/NHL57 fixtures are accepted. WNBA returns
  HTTP200 HTML to a bounded remote preview despite valid local JSON. Its separate
  default-off flag stops collection without deleting state or weakening admission.
  Website feeds stay off; 27 competition scopes remain deferred/unsupported.
- **Evidence**: 302 clean-worktree and 298 primary JS tests, primary TypeScript,
  focused zero-warning ESLint, Worker dry-run and redacted scan pass. Hosted
  monitor 36847037463 is healthy after the initial activation failure. Cricket's
  67-fixture audit, 39-fixture CPL and existing health/embed/3-provider contracts
  pass. A read-only exact-version tail observed the five-minute scheduled handler
  at 10:10:45 UTC with outcome ok; this is separate from the manually dispatched
  monitor. GitHub hourly sports timing and full device interaction remain open.
- **Consumer**: Owner build 112 uses an immutable pre-build receipt. Signed
  app/extension 112 installed/launched on exact Jet
  iPad; original container retained, manager and Home-curation keys match their
  pre-install fingerprints. Native sports cache validates 70 rows/31 lanes and the
  exact production revision; cricket validates 67 rows/three lanes, with receipts
  at 10:10:46 UTC. Actual landscape Home was captured and the installed
  process remained alive beyond60 seconds; no old Mac app substituted for evidence.
  Full reminder/provider/playback acceptance is not claimed.
- **New finding**: Native Home still shows football verification failure.
  Separate scoped PL/CL probes succeed with empty current-season windows. The
  legacy repository's empty-result premium fallback can throw unauthorized with
  intentionally empty bundled keys; transient proxy cooldown has another no-key
  failure cascade. Exact observed device error is not captured. This path was
  not changed or its warning hidden; qualify a focused repair before TestFlight.
- **Receipt safety**: Gitleaks classified the protected dashboard's public
  SankeyRenderer digest as an API key. The snapshot tool now accepts only that
  exact manifest/single-line/rule entry when it hashes the actual copied renderer.
  Other findings/errors still reject; dashboard files remain untouched. A full-line
  pattern and duplicate-key regression prevent JSON key collapse from hiding a
  secret. Thirteen offline tests include actual default-scanner rejection checks.

## 2026-09-30: Stage automatic app-wide fixture coverage without weakening source truth

- **Authority**: The owner approved implementing the app-wide extension after
  the cricket service. This is source-only implementation/local qualification;
  cloud/GitHub publication, activation, installs and TestFlight remain separate.
- **Implementation**: 30 source groups / 31 competition scopes, 28 bounded
  adapters and explicit boxing/PDC gaps. Per-source Durable Objects retain
  accepted UTC/participant/squad/status facts and immutable receipts; the shared
  cron checks adaptive five-minute / 15-minute / four-hour due times. Cold reads
  do not wait for all scrapes; hung registry slots expire independently.
- **Native**: One validated cache/consumer merges into the shared catalog,
  including failed-provider refresh paths and saved reminder identity. Existing
  cricket/football score owners and actual provider streams remain independent.
  Typed tournaments/sessions/cards do not fabricate opponents. Exact NCAA
  competition identity verifies college/women cohorts without requiring those
  words in a title; contradictory gender/youth/reserve evidence remains rejected.
- **Review repairs**: Stale hot receipts cannot become healthy after kickoff
  ages; multi-day live tournaments cannot silently disappear; future finals and
  terminal rollbacks reject; repeat confirmation proofs survive polls for offline
  clients. WNBA prior-year files cannot establish current empty coverage.
- **Monitoring**: A staged hourly workflow validates identities/coverage and
  newly fetches MLB/NHL/WNBA for current/imminent reconciliation. This is the
  same publisher, not independent-publisher proof. Fresh omissions/disagreements
  retain exact repeat hashes so continuously renewed receipts cannot conceal
  them; ordinary farther-future gaps remain informational. No paid credential or
  gated website feed is used by this crosscheck. Cricket's CWI monitor is intact.
- **Access / open gates**: Both sports flags stay zero. Publicly accessible
  ESPN feeds require a separate source-access resolution, not inferred reuse
  permission. Boxing/PDC source gaps, credentialed PL/CL bulk scope verification,
  protected publication/activation and named-device acceptance remain open. The
  retained Worker version identifies production cricket, not these staged edits;
  bump at the eventual deployment gate. Paid Coach stays disabled at limit 50.
- **Verification**: All 294 JavaScript tests (35 monitor/crosscheck) pass;
  TypeScript, lint, Worker dry-run, actionlint, redacted secret scans and the
  sequential simulator-free Catalyst unit / generic unsigned iOS Release gate
  pass, including 21 new native tests. New-file SwiftLint error fixed; style
  warnings remain. No old installed Mac binary was used as acceptance evidence.
  Owned temporary output is removed; about 48 GiB free. Details:
  `docs/operations/Sports-Fixture-Service.md`.

## 2026-09-30: Activate cloud cricket collection and the protected hourly monitor

- **Authority**: The owner approved the explicitly separate Cloudflare/GitHub
  activation gate. No native installation or TestFlight distribution was approved.
- **Activation**: Worker `88a5bce6-c694-435c-9b8c-6ac3173121de`, source
  `2026-09-30.cricket-fixtures-1`, retains existing budgets/secrets and adds the
  shared cricket registry plus registered five-minute cron. Protected PR27 merged
  as `1f4ce95e1e813c8cefd309dcec423c2a451f3320`; hourly workflow first production
  audit 36750055302 passes. Registration and manual dispatch are evidence, not
  proof of every future scheduled invocation.
- **Preservation**: Remote main predates September 20 production, so publication
  reconciles only the retained backend foundation and cricket dependencies.
  Existing runtime modules match the build-111 receipt; its entrypoint differs
  only by cricket integration. Paid Coach stays disabled with the existing
  group limit of 50. The older remote native access/draft contract is a separate
  publication/enablement prerequisite, not a reason to reopen paid calls.
- **Review fixes**: CodeQL caught repeated entity decoding and comment-removal
  token joins in the independent comparison parser. One-pass decoding and lexical
  masking, plus four regressions, resolve both findings. All required repository
  gates, CodeQL, GitHub Web CI (204 units, type/lint/dry-run/build), 200 local
  units and the 38-test live monitor pass. No protection bypass was used.
- **Live evidence**: 63 verified fixtures, two explicit pending pairings and zero
  sync failures. CWI independently agrees with all five upcoming West Indies
  fixtures in the window; South Africa–Australia is live, today's West Indies
  matches finished. Existing health, 39-fixture CPL, embed and catalog contracts
  pass with three responding catalogs. No football-live quota or paid API call.
- **Boundary**: One native update is still needed before testers consume the
  feed; the earlier 18-test native qualification remains separate from physical
  acceptance. No app build/install, TestFlight, public web deploy, tester/role,
  secret or paid-policy change. Owned temporary output is cleaned; ~52 GiB free.
  Codex blocked archival of the clean 23 MiB managed source checkout because
  this chat is pinned; build/dependency output was removed, protection preserved.


## 2026-09-30: Automate broader cricket coverage with durable state and independent supervision

- **Authority**: The owner approved implementing the discussed automatic
  fixture-update plan after observing an omitted current cricket match. Backend
  and GitHub publication were requested as a separate approval gate; no device
  installation or TestFlight release is authorized in this turn.
- **Decision**: Use the ICC website's structured international feed, retain CPL's
  separately reviewed authority, and store accepted revisions in one shared
  Durable Object. Routine collection is deterministic cloud work, not a model
  guessing/updating schedules. Keep coverage and stream availability separate.
- **Implementation**: Adaptive five-/15-/240-minute source refreshes, strict UTC
  and bounded-pagination validation, explicit live/terminal status, gender/youth
  identity, no stale receipt renewal, and conflict/missing-active admission guards.
  Native caching and five-minute failure retries consume the new route; current
  provider streams require both teams/squad and a 15-minute kickoff match.
  The hourly monitor independently compares CWI and deduplicates actionable or
  repeated failures. A six-hour read-only local Codex heartbeat investigates new
  failures with scoped sub-agents and stays quiet on unchanged states.
- **CPL correction**: The verifier's series summary moved matches21/22 one day
  later, while its individual match pages and CWI results support the existing
  official times. Exact reviewed exceptions restore the local 39-fixture audit
  without moving fixtures or renewing the bundled verification receipt.
- **Evidence**: Live local collection returns 63 named fixtures; ICC shows
  India–West Indies and South Africa–Australia live, and CWI independently matches
  India–West Indies. Two provisional pairings are explicitly pending, not
  invented. All 196 web/Worker tests, full simulator-free native gate (18 new
  cricket tests), type/lint/dry-run/build, actionlint and targeted secret scans
  pass. Temporary output is removed; about 52 GiB remains free.
- **Boundary**: Native integration needs one app update before testers benefit.
  Neither cloud deployment nor GitHub workflow publication occurred yet. The
  existing paid Coach policy is unchanged, no paid cricket API was added, and
  the next CPL season still requires source review. Do not promise every domestic
  league or interpret fixture discovery as successful playback.


## 2026-09-22: Measure private-beta participation from Apple instead of instrumenting Fotty

- **Authority**: The owner approved an alternative to tester-entered codes so
  they can distinguish active TestFlight participants from invitees who are not
  using the app.
- **Decision**: Keep participation reporting outside the iOS app. Read the
  existing App Store Connect beta-tester roster plus tester-grouped P7D and P30D
  usage metrics into a local owner-only dashboard. Do not add an analytics SDK,
  tester identity, background upload, privacy-manifest declaration or new
  tester interaction to Fotty.
- **Implementation**: `owner-tools/testflight-usage-sync` creates a ten-minute
  ES256 JWT, follows only bounded `api.appstoreconnect.apple.com/v1` pagination,
  joins metrics by Apple's tester ID and writes private names/emails to a
  Git-ignored `.local` snapshot. `owner-tools/testflight-usage-dashboard`
  presents factual categories—Recently active, Used this month, No recent
  sessions and Not installed—with filters, source evidence and an explicit
  measurement-limit disclosure. The tracked preview contains only invented
  `example.invalid` identities; live compiled output remains local and ignored.
- **Evidence**: Six focused Node tests pass for JWT signature/expiry,
  classification, ID joins, bounded pagination, exact P7D/P30D requests and
  evidence wording. The protected Data App build passes with separate data.
  Phone-width and 1280-point visual checks pass. A least-privilege Marketing
  team key now completes the live Apple sync: the local 22 September snapshot
  contains 11 testers, 10 active in P7D, 217 P7D sessions, 763 P30D sessions and
  zero P30D crashes/feedback. The rendered dashboard visibly identifies the
  App Store Connect source and contains no synthetic identities.
- **Boundary**: The private key is mode 0600 outside the repository. Real roster
  and compiled output remain ignored and loopback-only; the tracked fixture is
  still synthetic. This is a refreshable snapshot, not continuous telemetry,
  and Apple sessions do not prove feature use, playback success or duration.
  No iOS/TestFlight build, app privacy behavior or external service changed.

## 2026-09-20: Release the validated 2.0.1 batch as internal build 111

- **Authority**: The owner approved TestFlight deployment after the Worker and
  app release gates passed, then explicitly confirmed assigning the build to the
  existing internal group and saving the prepared testing notes.
- **Decision**: Distribute 2.0.1 (111) only through `Fotty Internal Smoke`; keep
  build 100 available as the fallback. Do not add testers, alter roles or
  notification preferences, create an external group, submit to App Review or
  publish Git source as part of this release.
- **Evidence**: The immutable pre-build receipt matched immediately before the
  signed archive upload. Xcode 27 reported `Upload succeeded`; Apple completed
  processing and App Store Connect showed build 111 as `Testing` at 12:57 AST
  with the 11-person internal group attached and focused English (U.K.) notes
  saved. The complete simulator-free native gate, 149 Worker/web units, lint,
  Worker dry-run and optimized web build passed. Owned archive, DerivedData,
  export and distribution-log output was removed; about 59 GiB remained free.
- **Boundary**: Availability is not exact-build physical acceptance. Install and
  exercise 111 through TestFlight on iPhone and iPad before widening the beta.
  No tester, role, external-testing, App Review, Git or additional Worker change
  occurred during distribution.

## 2026-09-20: Harden and deploy the single active Worker before splitting services

- **Authority**: The owner requested targeted Worker research, improvement and
  deployment of every active Worker, then asked whether multiple Workers would
  materially improve Fotty.
- **Decision**: Keep the current catalog, fixture, football-data and Coach routes
  behind one public Worker for this stability release. A Worker is already
  globally distributed; splitting stateless routes does not by itself improve
  latency or availability. Consider separating the paid Coach first only when
  independent secrets, budgets, permissions or release cadence justify the
  migration. Do not add a cron cache warmer without shared authoritative state.
- **Implementation**: Bound every remote catalog/fixture/football response and
  request time, preserve last-known-good CPL behavior, expose non-sensitive
  source/version/coverage headers, and emit structured provider events. Enable
  production logs with full invocation sampling and traces at five percent.
  Keep the direct embed fallback when catalog mirrors are partial or unavailable.
- **Evidence**: The final suite passes 149 Worker/web units, lint, workflow syntax
  and Wrangler dry-run; the production Next build passed before the first
  deployment. Deployment `1ce467d8-ce0c-46b3-9ce2-9fcfbdd18b00` reports
  source `2026-09-20.worker-stability-1`. Live verification returns the complete
  39-row CPL schedule with Antigua vs Jamaica in the Final and four PL schedule
  matches. Structured production telemetry shows both StreameX catalogs return
  530 from Cloudflare and Streamed Backup responds; lookup remains HTTP 200 with
  a direct fallback and `partial` coverage. API-Football rejected current-season
  live scores under the configured plan, and the Worker now advertises that
  restriction and defers another upstream attempt for four hours. A new
  deployment-level monitor verifies source identity, health, CPL integrity,
  catalog fallback and the embed redirect without calling the quota-consuming
  live-score route. It caught and fixed the redirect's missing version header;
  the final production monitor passes with the expected external warnings.
- **Boundary**: Paid Coach remains disabled with the approved group limit of 50
  attempts per day; no DeepSeek call, secret change, app/TestFlight build, cron
  trigger, web deploy or service split was performed. The daily GitHub monitor
  job is a local source change until separately published.

## 2026-09-20: Keep mirror telemetry internal, expose active Home filters and resolve CPL playoff identity

- **Authority**: During private iPad review, the owner rejected a permanent
  `Some broadcasts may be missing` banner and a same-day `Final` against `Teams
  to be confirmed`. They also observed that Browse Sports can fall too far below
  a populated match stack, but did not yet approve a replacement hierarchy.
- **Decision**: Keep partial-provider coverage as internal telemetry because one
  redundant mirror miss is not evidence that a visible broadcast is missing.
  Show customer-facing catalog notices only for a full refresh failure or stale
  verified-fixture authority. Name retained sport filters in Home's empty state
  and offer `Show all sports`. Preserve confirmed playoff
  stage plus both teams through the CPL manifest, client model and presentation.
  Stage-only future rounds use one honest title and no invented opponent badges.
- **Implementation**: The live verifier now contributes playoff participants
  only when both map to reviewed CPL identities; the official schedule remains
  kickoff authority. The current reviewed fallback records every 2026 playoff
  pairing and the final as Antigua & Barbuda Falcons vs Jamaica Kingsmen. Client
  reconciliation preserves known teams from a bundled or in-memory schedule
  while accepting a newer verified kickoff, preventing an old stage-only device
  cache from regressing identity. `CPL Final` remains visible as the competition
  label when teams are present.
- **Evidence**: All 141 web/Worker units and complete simulator-free iOS CI pass.
  Focused Swift checks cover silent partial-mirror telemetry, honest unresolved stages,
  confirmed Final identity, manifest parity and the cache/time no-regression
  case. Signed optimized 2.0.1 (110) installs and runs on Jet iPad; an exact-build
  screenshot shows Fight selected, Football reporting seven live events, the
  filter-specific empty state, `Show all sports`, and no routine mirror banner.
  Bounded output was removed.
- **Boundary**: Browse Sports remains in its existing location pending approval
  of a compact top-level sport picker. The updated Worker is source-checked but
  not deployed. No TestFlight, iPhone, tester, commit or Git publication action.

## 2026-09-20: Make Liquid Glass the real tab bar and reflow compact Home identity

- **Authority**: After private build 107 removed the duplicate blank surface, the
  owner clarified that Fotty should incorporate Liquid Glass into the actual
  Home/Matchday/FPL/Settings navigation and reported clipped sport/match names.
  The ongoing rebuild remains scoped to Jelani's iPhone.
- **Decision**: Use four genuine native `TabView` items and remove the parallel
  custom dock. Preserve Fotty's badges and sport art, but adapt composition to
  the real 375-point canvas: artwork above full-width sport labels, one line per
  team, a semantic secondary-list style and scaled reflow before trailing actions.
  Do not shrink essential identity to compensate for a rigid row.
- **Evidence**: The pre-fix screen reserved tile width for side-by-side icon/text
  and match-row width for badges, combined title, countdown and reminder. The
  first vertical tile pass measured 198 points and was rejected by the existing
  190-point regression; reduced excess padding passes without reducing touch
  targets. Complete simulator-free CI and the optimized device gate pass.
  CoreDevice reports and runs 2.0.1 (109); exact-build light/dark screenshots show
  the native glass bar and readable team names. The below-fold sport grid has a
  rendered compact-width pass but still needs owner on-device inspection.
- **Boundary**: No iPad, TestFlight, tester, backend, web, commit or Git action.

## 2026-09-20: Remove the duplicate iOS 27 tab surface after physical proof

- **Authority**: Owner reported a large blank bar on the private iPhone Home and
  unlocked that device for correction and verification. Scope remains the named
  iPhone; no iPad or TestFlight action.
- **Decision**: Do not place a hidden native `TabView` beneath Fotty's separate
  four-item dock. iOS 27 can expose that system surface as an empty Liquid Glass
  capsule despite hidden-toolbar configuration. Keep all four destination trees
  alive in a layered container, with only the selected layer drawn, interactive
  and accessible, so navigation and scroll state survive without duplicate chrome.
- **Evidence**: Build 106 physically proved that toolbar hiding and disabling
  minimization were insufficient. After the structural correction, full
  simulator-free CI and the optimized device gate pass. CoreDevice reports and
  runs private 2.0.1 (107) on Jelani's iPhone; a fresh 1125-by-2436 screenshot
  shows Home meeting Fotty's custom dock directly with no empty capsule.
- **Boundary**: Physical light-mode and larger-text acceptance remain open. No
  TestFlight, iPad, tester, backend, web, commit or Git publication action.

## 2026-09-20: Implement the approved Home concept on Jelani's iPhone first

- **Authority**: Owner approved rebuilding the final Apple-inspired Home concept
  on their iPhone for testing. This authorizes the native UI change and one
  private in-place iPhone install, not TestFlight, iPad or publication.
- **Decision**: Let one badge-led live panel establish hierarchy, use transparent
  compact paired-badge rows for Up Next, move Browse Sports after the schedule,
  and restore full-colour Apple equipment artwork in the established three-column
  phone grid. Keep glass restrained to the live panel and control chrome. Preserve
  the catalog, prioritization, countdown/reminder, Watch, playback and navigation
  owners rather than creating a preview-only parallel Home.
- **Evidence**: The existing rendered compact-grid test caught an oversized first
  pass and passes after tightening the tile. Complete simulator-free iOS CI and
  generic Release pass. Signed optimized 2.0.1 (105) installs in place on the
  named Jelani iPhone and CoreDevice reads that exact version. The device locked
  before automatic launch, so launch hold and physical visual acceptance remain
  open. Owned output was removed and disk returned to about 59 GiB free.
- **Boundary**: No iPad, TestFlight, tester, backend, web, commit or Git action.

## 2026-09-20: Close confirmed full-app audit defects without expanding release scope

- **Authority**: Owner requested implementation of every confirmed defect from
  the preceding read-only audit. This authorizes source fixes and proportionate
  local verification, not a device install, Worker deployment or TestFlight.
- **Decision**: Preserve user intent and system ownership instead of adding more
  UI state. Use native `TabView` for persistent roots, one app-level catalog
  lifecycle, reviewed HTTPS playback origins, attempt-scoped quality evidence,
  independent Watch Two recovery budgets, and data-declared CPL season topology.
  Add a network-level and global limiter to deterministic FPL scoring so rotating
  installation IDs cannot bypass abuse controls. Require an immutable source
  receipt capture/compare step for future shared builds.
- **Implementation**: Watch Two no longer resumes after an explicit pause merely
  because the network or foreground returns; failure of one pane cancels sibling
  resolution, terminal panes leave surviving audio usable, and score-triggered
  focus begins only after a real baseline. Web frames and catalog variants reject
  insecure, credentialed and unreviewed origins, and ATS arbitrary web loads are
  disabled. CPL validation accepts reviewed future seasons/new teams while a
  declared fixture count rejects truncation. UI coverage uses deterministic
  fixtures and iPad-only entry, with Dynamic Type, VoiceOver, Reduce Motion and
  safe-area corrections on the affected surface.
- **Verification**: Complete simulator-free iOS CI, Catalyst units and unsigned
  iOS Release pass. All 140 web/Worker unit tests, ESLint and Wrangler dry-run
  pass. All 30 release-source/memory tests and `git diff --check` pass. Temporary
  Xcode output was removed and disk space remained about 61 GiB free.
- **Boundary**: No device install, live playback claim, deployment, TestFlight,
  build-number change, commit or unrelated dirty-worktree cleanup occurred.

## 2026-09-20: Qualify build 104 installation and launch without overstating UI automation

- **Authority**: The owner unlocked Jet iPad to finish the already-approved
  private build-104 device gate. TestFlight remained a separate gate.
- **Decision**: Accept CoreDevice's exact 2.0.1 (104) inventory plus a bounded
  60-second foreground process hold as installation and launch evidence. Do not
  call Watch Two physically requalified when XCTest timed out enabling device
  automation before the UI test body began.
- **Evidence**: The unlocked device first reported and held build 104 for 60
  seconds. One Watch Two run stopped in Apple's automation initialization. After
  UI Automation was enabled, XCTest entered Fotty and selected Home, but Watch
  Two correctly remained absent for 15 seconds because the live catalog lacked
  two qualifying watchable matches. No player assertion executed. The runner
  and bounded outputs were removed; optimized Release 104 was restored, read
  back and held for another 60 seconds. Free space remained near 61 GiB.
- **Boundary**: Watch Two interaction on this exact build, real-match playback,
  PiP and TestFlight promotion remain open. No iPhone, tester, backend, commit or
  Git action occurred.

## 2026-09-19: Start 2.0.1 as a playback-confidence release in build 104

- **Authority**: Owner approved proceeding with the proposed 2.0.1 patch plan.
  Existing direction authorizes private Jet iPad qualification but keeps
  TestFlight as a separate decision.
- **Decision**: Advance the app and Live Activity extension together to 2.0.1
  (104). Carry forward build 103's accepted video-first Watch Two design and
  close a real observability gap: both MultiView panels now record attempts,
  decoded starts, recovery, failover, terminal failure and startup time under the
  same redacted, build-scoped quality contract as the normal player. Centralize
  the allowed playback context and test release identity across both targets,
  `project.yml` and their plists.
- **Why**: Prior Watch Two failures were invisible to Owner Status and opt-in
  beta reports, so an affected tester could supply a report while the local
  release evidence appeared healthy. A patch release should improve confidence,
  not duplicate already-implemented fixture, FPL and feedback systems.
- **Evidence**: Complete simulator-free CI passes. Live 2026/27 feeds contain
  380 PL and 144 Champions League fixtures; official CPL comparison passes all
  39 fixtures while preserving the reviewed match-28 exception; live football
  identity passes across three reachable provider feeds. The opt-in soak first
  exposed a removed URL helper and a fake-header proxy route, then passed its
  final 120-second direct Apple HLS hold with one request/source/item, decoded
  progress and zero failover. The final complete simulator-free gate passes
  again. The signed optimized
  Release and in-place Jet iPad install pass. Two UI attempts and automatic app
  launch were blocked because the iPad re-locked; the device then disconnected,
  so build-104 exact-version/process and interaction evidence remain open rather
  than inferred. Temporary roots and the UI-test helper were removed; no new
  crash report was observed before disconnect.
- **Boundary**: No TestFlight, iPhone, tester, backend, commit or Git action.
  Real-match playback/PiP and longer soak evidence remain separate from policy
  tests and installation.

## 2026-09-19: Make MultiView video-first in private build 103

- **Authority**: Owner approved fixing the undersized iPad playback surfaces and
  expects the physical interaction to be automated rather than manually delegated.
  This authorizes the Jet iPad candidate, not TestFlight or iPhone distribution.
- **Decision**: Wide iPad MultiView opens in Focus with one materially larger
  16:9 feed and one live secondary feed. Either numbered panel promotes in one
  tap; Equal remains explicit. Fit is the safe default and Fill now applies to
  web as well as native playback without replacing the source attempt.
- **Why**: Equal-width 590 × 704 web containers forced 16:9 media into about
  590 × 332 of visible content and presented the rest as meaningless black
  player area. Passing source/audio automation had not asserted video geometry.
- **Evidence**: On Jet iPad's 1180 × 820 window, automation measures the focused
  viewport at about 821 × 461 and the secondary at 352 × 198, validates both
  16:9, panel promotion, Equal, Fit/Fill/Fit, independent source changes, audio
  transfer and a 12-second stability hold. Full simulator-free CI and the signed
  optimized physical Release gate pass; build 103 is installed and running.
- **Boundary**: No TestFlight, iPhone, tester, backend or Git action. Human visual
  preference, audio quality, compact width and longer live soak remain separate.

## 2026-09-19: Qualify independent MultiView controls on Jet iPad

- **Authority**: Owner requested an app-controlled test of the redesigned
  two-match player on the connected iPad. This authorizes a private device
  install and automated interaction, not TestFlight distribution.
- **Decision**: Keep Source and Audio controls permanently visible in each
  panel header. Source changes reload only their owning panel; Audio explicitly
  selects which panel is audible. Keep browser playback controls interactive and
  retain one global Close/Swap/Fill-or-Fit toolbar.
- **Automation**: Add stable identifiers for entry, ordered event selection,
  per-panel source/audio controls and panel presence. Do not assign an
  accessibility identifier to the shared header container because it collapses
  its children's distinct identities.
- **Evidence**: A physical Jet iPad UI journey selected two current matches,
  changed panel 1 to Source 2 while panel 2 stayed on Source 1, changed panel 2
  independently, moved audio to panel 2 and held both panels for 12 seconds. The
  complete simulator-free CI gate and signed optimized Release gate pass.
- **Device and cleanup**: Private 2.0.0 (102) is installed and running on Jet
  iPad. Fotty's UI-test runner was removed after the journey. No TestFlight,
  iPhone, tester or backend action was taken; owned temporary output was removed.

## 2026-09-19: Unify sport identity and make two-match playback truthful

- **Authority**: Owner requested fixes to the icon system and a full review and
  update of the Watch two matches experience. This is source implementation and
  local qualification only; no install, build-number change or TestFlight action.
- **Decision**: Replace platform-variable emoji sport art with one category-aware
  SF Symbol family in a stable tinted emblem. Cover the catalog's football,
  American football, rugby, cricket, basketball, baseball, hockey, tennis,
  combat, motorsport, darts, golf, volleyball, table tennis and college variants,
  with one explicit generic fallback.
- **Two-match interaction**: Use one user vocabulary (`Watch two`, `Choose two
  matches`, `Two-match view`), show only live/imminent events with active catalog
  sources, preserve tap order as positions 1 and 2, and acknowledge Start before
  concurrent resolution. Recent positive health may rank resolution but may not
  hide the manual two-match action.
- **Player ownership**: Browser-backed panels retain provider play/pause controls;
  Fotty does not show a native button that cannot control them and no longer puts
  a whole-panel tap gesture above the web surface. Explicit 44-point source/audio
  actions choose the source and audible panel. Native panels retain working app
  play/pause, and automatic goal-audio appears only for two football matches.
- **Verification**: The complete simulator-free gate passes provider/catalog
  checks, the full Catalyst unit suite and an unsigned generic iOS Release build.
  The first render pass caught an over-tall compact sports grid; the emblem was
  returned to its original footprint and the complete gate then passed. Physical
  iPhone/iPad appearance, provider controls and simultaneous live playback remain
  open. The bounded DerivedData root was removed; free disk remains 63 GiB.

## 2026-09-19: Install app-wide UI candidate 101 on Jet iPad; preserve shared 100

- **Authority**: Owner explicitly approves installing the completed UI update on
  Jet iPad for physical verification. This does not authorize TestFlight, iPhone,
  backend or Git actions.
- **Decision**: Allocate private build 101, build a signed optimized Release with
  official Xcode 27, install it in place and preserve the existing app container.
  Keep shared internal build 100 unchanged.
- **Evidence**: App and Live Activity extension are 2.0.0 (101), arm64 and
  strictly signed; the profile contains the exact iPad. CoreDevice confirms the
  installed version. The app survives a 60-second launch hold and two fresh crash
  queries return zero Fotty files. Physical original-resolution screenshots show
  full-width Home, two-column Matchday, wide disconnected FPL and grouped Settings
  without clipping or side bars.
- **Follow-up acceptance**: After the owner connects FPL, the same app container
  contains a valid manager ID and current-season confirmation. A full
  terminate/relaunch opens the connected Live workspace without ID re-entry and
  still produces no crash log. Do not copy the numeric ID into documentation.
- **Device state**: The display-only developer viewer did not justify a UI-test
  helper. Fotty's own Matchday route and only the selected-tab preference exposed
  the remaining primary tabs. The full preference file was preserved and the tab
  was restored to Home; no manager, theme, interest, source or notification data
  changed.
- **Open gate**: Real interaction checks for Search, Light/System, accessibility
  text/narrow window, connected Coach keyboard/drafts, player/source recovery,
  playback and PiP. No TestFlight upload or blanket owner acceptance claimed.
- **Cleanup**: Remove only the bounded task-owned build output, screenshots and
  temporary preference copies after documentation; keep the installed app/data.
- **Evidence file**: `docs/releases/Fotty-2.0.0-101.md`.

## 2026-09-19: Complete app-wide UI source polish; retain honest visual gates

- **Authority**: Owner rejects stopping at the initial narrow polish pass and
  asks to continue until the intended Apple-aligned app-wide work is finished.
  Source implementation/qualification is in scope, not distribution or installs.
- **Decision**: Apply existing design contract across Home, Matchday, Search,
  every FPL workspace/tool, Settings/onboarding, Match Hub/insights and player
  source/recovery presentation. Preserve sports art, badges, compact normal rows,
  normal phone grid, useful wide layouts and existing tab/session ownership.
- **Interaction**: Adaptive labels/actions, semantic button regions, selected and
  disabled feedback, Increase Contrast/Reduce Transparency support. Coach setup
  and messages scroll together; FPL retains native keyboard avoidance without
  replacing the root tree. Match Hub has one scroll owner and measured Close
  inset. Failed active source's Retry label now matches its existing callback.
- **Verification**: 586 full Catalyst units pass with two opt-in live/soak skips.
  Current component renders and independent cross-reviews completed. Stale
  source-shape assertions corrected without dropping their behavioral guardrails.
  Unsigned iOS Release compilation passes. Both unsigned and signed integrated UI
  runners are killed before connection; current macOS security logs confirm the
  launch denial despite valid signed bundle. No security bypass or old Mac app
  substitution. UI journeys were authored but did not execute.
- **Open gate**: Physical keyboard, large-text, theme, navigation and playback
  presentation acceptance. Installation question for Jet iPad remains unanswered.
  No version bump, install, TestFlight, backend, commit or push.
- **Cleanup**: Removed the single 1.4 GiB temporary build/result/render directory;
  no lingering app/test runner or unrelated cache removal. Final 63 GiB free.
- **Evidence**: `docs/audit/Fotty-Appwide-UI-Completion-2026-09-19.md` separates
  implementation, automated renders, blocked native automation and owner sign-off.

## 2026-09-19: Apply the UI standard to scoped interaction and grouping polish

- **Authority**: Owner says proceed after the Apple-grounded design-skill work.
  This pass is source-only, not an installation or a shared beta update.
- **Decision**: Keep the approved composition, identity art and behaviour. Add
  stationary press feedback to opted-in Home/Watch/reminder controls; make
  Settings action/navigation-row feedback visible in both themes. Remove the
  nested Search channel card and align consequential Matchday schedule notes.
- **Boundary**: No FPL logic, fixture policy, source selection, playback/PiP,
  reminders policy, backend, version, device installation or TestFlight changes.
  Shared consumers were checked; no new whole-screen gestures or animations.
- **Verification**: 137 focused Catalyst unit/render checks and unsigned iOS
  Release pass on official Xcode 27. Independent source review finds no blocking
  regression. Offscreen component renders were inspected; physical touch,
  navigation, appearance and Dynamic Type acceptance remain open. Fix the visual
  harness's sample-clock mismatch rather than accepting misleading evidence.
- **Evidence**: `docs/audit/Fotty-UI-Interaction-Polish-2026-09-19.md`. Keep device
  screenshots and actual interaction separate from compile/render evidence.

## 2026-09-19: Strengthen native UI design guidance and visual acceptance

- **Authority**: Owner requested improved UI/design skill close to Apple guidance.
  This is instruction/documentation work, not a new app redesign or release.
- **Decision**: Add reusable personal `apple-ui-design` guidance and the repository
  `docs/FOTTY-UI-DESIGN-STANDARD.md`; route UI tasks from AGENTS and the Apple baseline.
- **Standard**: Ground material decisions in current HIG; preserve Fotty's sports
  identity. Specify hierarchy and adaptation before broad edits, then compare
  exact native renders against approved references. Treat visual inspection,
  interaction, automation and owner acceptance as separate evidence.
- **Boundary**: No app source, assets, version, devices, backend, GitHub or TestFlight
  changed. The skill improves the process; it does not prove existing UI quality.
- **Verification**: Skill/YAML/link validation, whitespace and memory-export checks
  pass. An independent discussion-only scenario preserves identity, touch targets,
  material hierarchy and evidence limits; clarify provisional offline feedback.

## 2026-09-14: Ship internal build 100 using verified official Xcode 27

- **Authority**: Owner approved the toolchain update and existing internal group;
  no new testers, direct installs, public release, backend deployment or Git push.
- **Toolchain**: Owner completed required components for official Xcode 27
  (27A266a). Every gate/export explicitly pins its developer directory; global
  xcode-select still names the older beta. No simulator runtime downloaded/booted.
- **Qualification**: Fresh 658-file pre-build receipt; 581 Catalyst tests pass,
  zero failures, two explicit opt-in skips; iOS Release and signed archive pass.
  Source/working copies matched before upload. Nested identities, signatures,
  arm64, dSYMs, icons, three manifests, empty provider keys and audio mode verified.
  Existing synchronous audio-session warning remains. Live identity passed two
  feeds; the third timed out. Backend health/sourceVersion matches; no deployment.
- **Distribution**: Xcode upload succeeds at 15:12 AST. Apple completes processing;
  built-in encryption declaration and English (U.K.) test notes saved. Existing
  Fotty Internal Smoke assigned. Fresh Apple UI confirms 100 Internal / Testing,
  11 invitations around 15:17 AST. No installs reported, email delivery unverified.
  Build 93 preserved as fallback. CS remains opt-in; physical acceptance stays open.
- **Cleanup**: Remove finished 1.9 GiB installer, 1.1 GiB temporary release root
  and exact distribution log. Keep 17 MB immutable source recovery receipt; no
  older Xcode/cache deletion. Final 65 GiB free. See release 100 for hashes.

## 2026-09-14: Verified Xcode 27 awaits protected Mac setup authorization

- **Evidence**: Owner saved/extracted official Xcode 27 (27A266a). Strict deep
  signature validation and Gatekeeper Apple System assessment pass. Move the app
  to `/Applications/Xcode.app`; preserve both older toolchains, no duplicate copy.
- **Boundary**: Required-component installation is waiting on SecurityAgent.
  Owner must authorize with the Mac password. No credentials accessed, new
  license accepted, simulator runtime selected or developer default changed.
- **Release state**: No candidate-100 build/upload yet. Apple still shows 93
  Internal / Testing for Fotty Internal Smoke (11 invitations, 10 installs).
  Keep the 1.9 GiB task installer until setup succeeds, then clean it; 63 GiB
  free. Existing beta installer and unrelated caches are untouched.

## 2026-09-14: Approved Xcode update awaits an owner-downloaded installer

- **Authority**: Owner approved updating Xcode without simulators, then rebuilding
  for the existing internal TestFlight group. No additional distribution scope.
- **Evidence**: Apple's Applications page lists final Xcode 27 (27A266a), released
  today. In-app downloads are blocked; unauthenticated CLI returns 403. No new
  installer was saved, no toolchain changed, 68 GiB remains free. Existing beta
  installer and installed Xcodes are preserved.
- **Next gate**: Owner downloads the official installer in Safari. Verify its
  signature/build, handle any new license with the owner, then requalify before
  upload. Build 93 remains shared; do not reuse the rejected beta archive.

## 2026-09-14: Build 99 qualifies locally but Apple rejects the old beta toolchain

- **Authority**: Owner approved final checks and the existing internal TestFlight
  group. No new testers, device installs, backend deployment or Git publication.
- **Evidence**: 581 units pass under public Xcode 26.6; its generic iOS destination
  is unavailable. The Xcode 27 rerun from the verified temporary source copy
  passes 581 units, two opt-in skips, iOS Release and signed archive validation.
  A Documents permission prompt interrupted the original-path run; no broader
  permission was granted. Preserve both the interruption and clean rerun evidence.
- **Boundary**: Apple's upload validator rejects 27 beta 5 despite dated August
  acceptance notes. Current RC is required. Do not falsify toolchain metadata,
  redownload simulators or declare upload/group access successful. Obtain owner
  approval before the large Xcode update. Shared build remains 93.
- **Traceability**: Saved a verified 17 MB pre-build source receipt, compared
  original and restored trees before upload, and removed all owned build output.
  No snapshot uploaded to GitHub. See release 99 for hashes and cleanup evidence.

## 2026-09-14: Owner accepts CS2 playback, source controls and PiP on private 98

- **Evidence**: Owner identified CS2 as playing, then confirmed pause/resume,
  opening Sources and switching back to StreamEx all work on the test iPad.
  The owner subsequently confirmed “pip works”.
- **Boundary**: Record these as passed for that session, not every CS option.
  Timed background soak, lock/unlock, other variants and loading-time switching
  remain unconfirmed.
  No source changes, build, install or TestFlight action in this acknowledgement.
  See release 98 for the precise scope of the accepted test.

## 2026-09-13: Install CS correction build 98 on Jet iPad only

- **Authority**: Owner approved the private device gate after the CS-only audit.
  No further functional code changed; app/extension versions advance to 98.
- **Evidence**: Signed optimized Release, nested signatures, installed versions,
  landscape Home and a 54-second same-process hold pass. CS remained enabled
  across the in-place update. No new Fotty incident was listed in that window.
- **Boundary**: Actual CS decoded controls/source switching/PiP still need owner
  acceptance. No iPhone, TestFlight, UI-test helper or app-data reset. Owned build
  and inspection output removed; disk remains 70 GiB free. See release 98.

## 2026-09-13: CS uses shared playback routing and retains attempt ownership

- **Scope**: Owner clarified recent changes are playback/CS sources, not FPL.
- **Decision**: Route by typed delivery/endpoint, not a nested query URL; reuse
  the rule in MultiView. Direct HLS retries native once, never as an invented
  webpage. Real web handoffs retain their original fallback and source metadata.
- **Lifecycle**: Recheck cancellation/source/attempt after validation; PiP input
  commands publish after UIView updates, and dismantled surfaces stop callbacks.
- **Admission/tracking**: Preserve reused-ID conflicts before matching; permit
  exact Live-catalog fallback if the sport catalog is missing/broken. Keep CS
  numbering and add hidden hashed source attribution to bounded local events.
- **Boundary**: Source-only gate, not a new install or TestFlight release. Jet
  iPad remains 97; physical CS control/switch/PiP acceptance is still required.
  See `docs/audit/Fotty-CS-Playback-Integration-2026-09-13.md` for test evidence.

## 2026-09-13: Native player callbacks must not publish during SwiftUI updates

- **Finding**: Builds 94-96 could render CS HLS but then leave every visible
  control unresponsive. The device's build-95 incident is a FrontBoard
  `0x8BADF00D` scene-update watchdog. Its main-thread stack repeats
  `updateUIView` -> callback assignment -> playback-state mutation -> SwiftUI
  update; the sampled URL classification is incidental, not the root cause.
- **Decision**: Callback properties on `PlayerUIView` are passive assignments.
  Ready/display, time-control and PiP availability publish only from their real
  AVKit/KVO observations. Preserve build 96's dynamic hit-test ownership: the
  native surface reveals controls while hidden and yields once controls appear.
- **Gate**: A regression proves callback reassignment emits no state, the
  hit-test regression still passes, and signed private build 97 is installed
  only on Jet iPad. A 15-second CS playback/control/switch-back check remains
  required before TestFlight.

## 2026-09-13: Add an opt-in CS stream lane without changing fixture authority

- **Decision**: Add a third, off-by-default playback module whose user-facing
  sources are opaque `CS1`, `CS2`, and so on. Fotty consumes the add-on's
  Stremio `manifest`, `catalog` and `stream` contracts; it does not copy the
  client/add-on UI or use the remote catalog as a fixture source.
- **Identity/safety**: A request must match exact sport, both whole-team
  identities and kickoff within 15 minutes. Multiple IDs conflict rather than
  choosing the first. Only HTTPS responses and same-origin `/api/manifest` or
  `/watch` deliveries are admitted; cross-origin, arbitrary-path and P2P/Ace
  results fail closed. Channel rows and undated events are not inferred as a
  named match.
- **Integration**: The independent lane shares the existing 18-second attempt
  deadline and attempt-scoped health/failover. Existing providers keep their
  neutral Broadcast labels; only the CS lane exposes its opaque family labels.
  The bundled toggle defaults off for existing and new installations.
- **Verification/boundary**: Exact/reversed-pair, category, kickoff,
  youth/senior, ambiguity, delivery allowlist, deduplication, player routing and
  opt-in defaults are covered by Catalyst tests; the complete simulator-free
  Catalyst and generic iOS Release gate passes. No device install, TestFlight,
  backend deployment, remote fixture change or decoded-playback claim.

## 2026-09-13: Keep confidence evidence private and make time transitions absolute

- **Decision**: Reuse Fotty's bounded, privacy-safe quality history for a hidden
  Owner Status view, filtered to the exact installed version/build. Reveal it by
  seven taps on the Settings version row; never restore engineering messages to
  Home. Contextual playback reports may seed an empty draft but cannot overwrite
  existing tester work or silently enable diagnostic sharing.
- **Temporal correctness**: FPL deadline notifications now use absolute UTC
  calendar components including seconds and carry a typed route back to the FPL
  gameweek workspace. Kickoff alerts require scheduled/timed to in-play, so
  halftime or suspension recovery cannot create a second kickoff alert.
- **Verification/boundary**: New tests cover build attribution, draft preservation,
  UTC/DST-resistant notification construction, FPL destination ownership and
  kickoff transitions. The complete simulator-free Catalyst unit and generic iOS
  Release gate passes. No device install, TestFlight/backend change, remote
  analytics or physical notification/visual acceptance is claimed.

## 2026-09-13: Watch acknowledgement owns the first presentation frame

- **Decision**: Home, Matchday and Match Center set their stream-resolution UI
  before discovery, yield a bounded 60 ms presentation window, acknowledge the
  accepted action with a light haptic and ignore a repeated tap for the same
  in-flight event. A different event can still replace the active lookup.
- **Why**: Provider catalog matching can begin before SwiftUI commits the loading
  surface. With visually plain Watch controls, a user could reasonably believe
  the tap was missed and tap again, restarting the same request and extending
  the apparent delay.
- **Verification/boundary**: A regression protects all three entry points and the
  complete simulator-free Catalyst unit plus generic iOS Release gate passes.
  This is source validation, not physical-device timing evidence; it is not
  installed or distributed.

## 2026-09-09: Verify off-Mac recovery in a separate private GitHub repository

- **Authority**: Owner chose GitHub and approved creating `fotty-recovery`.
  Authenticated owner is `jetboss`; the exact repository did not previously
  exist. Create it Private and disable Actions before uploading any files.
- **Storage**: `https://github.com/jetboss/fotty-recovery`, outer storage commit
  `f54a314dc03ea24eefd535b9455c9f26f275b64e`, contains restore instructions and
  the unchanged 17 MB build-93 bundle/receipt, not the development Git history.
- **Verification**: A fresh clone from GitHub matches both original files
  byte-for-byte. Disposable source restore validates all 645 files/modes,
  source commit and hashes and passes Gitleaks. Private visibility and disabled
  Actions are verified after upload. The owned 70 MB staging root is removed;
  the original local recovery bundle stays, with approximately 48 GiB free.
- **Boundary**: No change to the working repository's origin/index/history,
  TestFlight, app source, devices, backend or collaborators. No scheduled backup.
  The saved post-release snapshot predates local performance-feedback changes;
  it is not exact historical binary provenance or automatic protection for
  future edits. See `docs/operations/SOURCE-RECOVERY.md` for the restore procedure.

## 2026-09-09: Prepare recovery, opt-in field evidence and independent build-93 testing

- **Scope**: Owner approved the blind-spot follow-up. Source/local gates only;
  no device install, TestFlight upload, new tester, remote Git publication,
  backend/paid-service change or automatic analytics.
- **Recovery**: Capture current app source before feedback edits into a verified
  17 MB, 645-file independent one-commit bundle. No old ancestry or active-index
  mutation. Receipt/restore procedure and future pre-archive capture/compare
  gate are in `docs/operations/SOURCE-RECOVERY.md`. The post-release capture
  does not prove exact original build-93 inputs. Off-Mac destination is pending.
- **Evidence**: Existing feedback consent now exports the latest dated scroll
  and hang scalars with reporting windows, reported/mixed build attribution and
  honest unavailable state. At most two <=2 KiB summaries, 14-day retention,
  corruption/ordering guards and late-pre-clear rejection. No raw MetricKit
  payloads, traces, private metadata or silent upload.
- **Qualification**: Eight Python recovery tests and actual snapshot restore/
  Gitleaks verification pass. Full public-Xcode gate: 546 Catalyst units pass,
  zero failures, two opt-in skips; generic iOS Release passes. Owned 953 MB
  temporary output removed; approximately 48 GiB free.
- **Boundary**: Build 93 remains the recorded shared candidate; changes above
  are unreleased after 93. `docs/beta/BUILD-93-QUALIFICATION.md` prepares entry
  checks, five uncoached tasks, a seven-day ledger and verified report receipt.
  Physical/independent acceptance is not complete and no reports were sent.
  See `docs/audit/Fotty-Field-Readiness-2026-09-09.md`.

## 2026-09-08: Ship shared UI batch 93 to the existing internal group

- **Authority**: Owner requested TestFlight deployment. Allocate 2.0.0 (93)
  after private 92; no feature/test code changes, tester/role changes, external
  testing, direct-device installs, backend deployment or Git publication.
- **Scope**: Batch private 82–92: compact Home, app-wide grouping, badges and
  equipment, adaptive iPad width, optional kickoff clashes, consistent clocks,
  quieter routine refreshes and shaded sport loading motion.
- **Qualification**: Fresh metadata audit reaches three feeds without conflicts;
  five identity vectors pass. Full public-Xcode Catalyst units: 538 pass, two
  opt-in live/soak tests skip. Four refreshed UI checks pass on Xcode 27. Initial
  kickoff automation did not advance its test clock; unchanged rerun passes.
  Record this intermittent test action, not an invented production fix.
- **Distribution**: Public Xcode 26.6 (17F113) archive passes app/widget versions,
  strict signatures, minimum OS and production-default checks. Apple accepts
  internal-only upload with symbols at 21:31 AST, completes processing and the
  established encryption declaration, and shows 93 Internal / Testing after
  saved What to Test notes and assignment to the existing eight-person Fotty
  Internal Smoke group. Fresh group count supersedes historical seven-person
  notes. Build 81 remains Testing as the previous shared fallback.
- **Boundary**: TestFlight download/email delivery, real device UI/motion/power
  and live playback acceptance remain open; direct iPad 92 is not certification
  of the TestFlight artifact. Owned 2.3 GB release output and distribution log
  are removed, about 47 GiB free. See `docs/releases/Fotty-2.0.0-93.md`.

## 2026-09-08: Shaded sport loaders and private Jet iPad build 92

- **Authority**: Owner approved the loader redesign and iPad deployment, not a
  TestFlight release. Home tile artwork and established playback remain intact.
- **Implementation**: One bounded native Canvas draws original equipment with
  stationary lighting, sport-specific movement and contact shadows. Rugby is
  distinct from NFL. Pure pose math is loop-continuous; motion pauses offscreen,
  inactive, under Reduce Motion or Low Power Mode, with observed power changes.
  No sound, haptics, downloaded media, new dependency or artificial loading delay.
- **Identity**: Blue/silver Champions League treatment requires explicit UEFA/UCL
  metadata or an official match agreeing on whole team identities and kickoff.
  Youth, women's, confederation conflicts and catalog conflicts stay generic
  football. This does not modify competition filtering or infer match status.
- **Evidence**: 169 focused Catalyst checks pass, one opt-in playback soak skips.
  Four-phase dark/light native artwork inspected; initial Canvas compile and
  one-level render-rounding test issues corrected before final qualification.
  Signed Release/strict app+widget signatures, installed version 92 and 30-second
  main-app hold pass on Jet iPad. Home retains current CPL Watch and interests.
- **Boundary**: No stream was started and no physical loader/power/hitch claim
  is made. iPhone stays 90; recorded TestFlight stays 81. Owned temporary build
  output is removed; details and acceptance are in release 92 and
  `docs/audit/Fotty-Sport-Loading-Motion-2026-09-08.md`.

## 2026-09-08: Install the Home clock fix as private build 91 on Jet iPad

- **Authority**: Owner requested iPad deployment only. App/widget and the
  XcodeGen manifest advance together to 2.0.0 (91); no feature edits or project
  regeneration during deployment.
- **Evidence**: Jet iPad was connected/unlocked on 90. Optimized signed Release
  and strict nested signatures pass; CoreDevice verifies installed 91 and a
  successful 30-second startup hold. Actual portrait Home at 20:26 shows the
  current 19:00 CPL match once with Watch, full width, without the old countdown
  or routine stale banner. No playback was started.
- **Boundary**: iPhone remains 90 and TestFlight 81. No simulator, device UI-test
  runner, settings/data reset or FPL identity action. Only the owned temporary
  deployment output is removed. See release 91 for remaining physical acceptance.

## 2026-09-08: Keep Home time, sections and adaptive rows consistent

- **Report**: Jet iPad showed Cricket “1 on now” while a started CPL fixture
  retained “Starts in 1h 5m” and a stale paired row duplicated tomorrow's match.
- **Change**: Project a single identified sequence of Home headings/rows before
  lazy rendering. Row identity includes section, ordered members and columns;
  rendering consumes that explicit column value. Clock ticks keep stable IDs.
  Visible controls no longer receive the cached catalog item's timestamp.
- **Refresh**: Restart the local clock on activation/catalog change and wake at
  kickoff even within one minute. Share a 90-second automatic attempt throttle;
  cancellation allows retry. Routine cache/age copy is silent without advancing
  receipts or concealing real fetch/partial/CPL verification failures.
- **Evidence**: 137 BetaUsability/HomeDiscovery/SportsCatalogRefresh/MatchReminder
  units pass. Six focused Catalyst checks pass (transition/navigation, filters/
  full lineup, large text, stale CPL, offline and partial notices). The transition
  test was strengthened and rerun for a genuinely narrow, full-width card.
  Generic unsigned iOS Release compilation and whitespace/shell checks pass.
  Direct native test-app inspection confirms current/next rows. Early automation
  initialization failures and two corrected test assumptions are documented in
  `docs/audit/Fotty-Home-Clock-2026-09-08.md`; they are not app regressions.
- **Boundary**: Source only; no provider/backend changes, version increment,
  device installation, TestFlight, simulator or production preference changes.
  Physical kickoff/foreground/rotation acceptance awaits an authorized install.
  Both owner devices remain 90; TestFlight remains 81. One bounded temporary
  gate is cleaned after verification.

## 2026-09-08: Complete private build 90 delivery on both owner devices

- **Retry evidence**: Both named devices connected and unlocked. A fresh optimized
  signed app/widget 90 passed strict signatures. CoreDevice verifies 2.0.0 (90)
  installed on Jelani's iPhone 15 Pro Max and Jet iPad Air 4. Both launch and
  survive 30-second process holds. The earlier connection/lock blocker is resolved.
- **Scope**: Same approved optional-clash/UI source, no further feature edits or
  version increment. No TestFlight, simulator, device UI-test runner, data reset
  or FPL identity confirmation. Visual/playback acceptance is distinct from startup.
- **Cleanup**: The one bounded retry build directory was trap-cleaned after both
  devices were verified; approximately 48 GiB free. See release 90.

## 2026-09-08: Build private 90; device installation awaits unlocked connections

- **Authority**: Owner requested installation on Jelani's iPhone and Jet iPad.
- **Build**: One optimized signed iOS Release artifact passed strict nested
  signatures; app/widget both report 90. Synced the XcodeGen manifest's stale
  build number with the active project, without regenerating the project.
- **Outcome**: iPhone installation hit CoreDevice disconnect error 4000; iPad
  installation hit error 3002/closed remote connection. Fresh installed-app
  queries confirm iPhone remains 87 and iPad 89. Both now require unlocking.
  Do not claim successful delivery or increment past 90 merely for the retry.
- **Boundary**: No TestFlight, data reset or device UI-test runner. Temporary
  signed/build products were trap-cleaned after failure; about 48 GiB free.
  Retry the same intended build after the owner unlocks and connects both devices.

## 2026-09-08: Make kickoff clashes optional and off by default

- **Owner feedback**: The landscape fix is accepted. The kickoff-clash hint no
  longer feels useful enough to occupy Matchday by default.
- **Decision**: Keep an opt-in under Settings → Preferences, labelled “Show
  kickoff clashes”, with one short explanation of overlapping My Matchday games.
  It is not a push notification and does not belong under permission controls.
- **Implementation**: Shared persisted preference, default off for new/existing
  installs without an explicit choice. Gate both the banner and conflict scan;
  include the choice in the cached projection key. Preserve saves and reminders.
  Private backups retain the choice; older backups restore it as off.
- **Verification**: All 78 BetaUsability/SportsPersonalization/PrivateBackup tests
  pass, including default-off, saved preference, reminder independence and older
  backup restore. Four Catalyst checks pass: opt-in across navigation, grouped
  notification controls and Settings/Matchday Dynamic Type. Generic unsigned iOS
  Release compilation, shell syntax and whitespace checks pass. No simulators;
  the one bounded validation directory was trap-cleaned (about 48 GiB free).
- **Boundary**: Source-only; no build-number change, device install or TestFlight
  upload. Jet iPad remains 89 and still needs a later install for this change.

## 2026-09-08: Use the iPad's available width in private build 89

- **Cause**: Jet iPad's 1180-point landscape screenshot showed narrow content
  caps, nine sport tiles plus a lone tile and a broken Motorsport label.
- **Decision**: Adapt to actual window width, not device orientation. At 1000
  points, use two-card fixture rows and side-by-side Settings/FPL groups; narrow
  windows and accessibility text retain one column. Balance tablet sports rows
  without changing phone overflow or catalog ordering/data ownership.
- **Regression fixes**: Preserve the existing compact grid height with padding
  adjustments; make the complete FPL workspace-tab label clickable. Use AnyLayout
  for non-destructive rearrangement and keep lazy fixture rows bounded to two.
- **Evidence**: 142 focused units and 13 distinct Catalyst UI journeys pass,
  including actual wide/narrow resizing with FPL state retained. Signed Release,
  strict signatures, exact installed version and 30-second launch hold pass on
  Jet iPad. Its actual Home screenshot confirms full-width content, five-plus-five
  sports and two-column match cards. Other physical screen/appearance acceptance
  remains open; fixture warning/service health and playback are separate.
- **Authority**: Explicit Jet iPad install approval only. No iPhone/TestFlight
  update, data/consent reset or device UI-test runner. Owned validation output
  and screenshots removed; approximately 48 GiB free. See release 89 and the
  iPad layout audit for scope and validation limits.

## 2026-09-08: Install the finished UI polish as private iPad build 88

- **Authority**: Owner requested iPad deployment for testing, not TestFlight.
- **Evidence**: Fresh signed optimized Release build, strict nested signatures,
  CoreDevice installed-version verification and launch pass on Jet iPad (iPad Air
  4th generation). App/widget build numbers advanced together to 88.
- **Boundary**: No iPhone update, TestFlight upload, data reset or UI-test runner
  install. Physical iPad visual acceptance remains with the owner. Temporary
  build output removed. See `docs/releases/Fotty-2.0.0-88.md`.

## 2026-09-08: Finish the build 87 visual-review findings locally

- **Decision**: Preserve the approved calm presentation and existing behaviour;
  finish the specific remaining hierarchy/grouping issues before another install.
- **Implementation**: Shared Matchday reasons appear once per section; kickoff
  clash details expand on demand while the warning stays visible. Settings has
  a compact leading title and explicitly visible pushed navigation bars. Search
  rounds its group ends without replacing lazy rows. FPL setup puts the team
  check above optional link help and retains confirmation/local-data safeguards.
- **Verification**: All 108 BetaUsability/FPLTrust tests, generic iOS Release
  compilation and five Catalyst checks pass: Matchday/Settings Dynamic Type,
  grouped notifications, Help/feedback navigation and non-connecting FPL input.
  Temporary build output is removed. UI test summaries also carried a generic
  main-thread runtime warning; this pass does not diagnose it or claim measured
  performance improvement.
- **Boundary**: Source-only finishing pass; installed owner build 87 and recorded
  TestFlight 81 are unchanged. Physical visual acceptance remains separate,
  especially the real FPL workspaces awaiting owner team confirmation.

## 2026-09-08: Install app-wide UI build 87 and record real visual gaps

- **Evidence**: Signed Release/signatures, exact-device installation/version and
  launch pass. Mirroring reviewed Home, Matchday, Settings/Notifications and
  cricket search. Temporary query cleared and Home restored; no settings changed.
- **Findings**: Repeated Matchday reason labels, competing notices, dense FPL
  confirmation, inconsistent header spacing and square search grouping remain.
  FPL workspace review is blocked on owner identity confirmation, not bypassed.
- **Boundary**: TestFlight unchanged; no playback or iPad/light/large-type physical
  qualification. Owned output cleaned. See `docs/releases/Fotty-2.0.0-87.md`.

## 2026-09-08: Owner defines current milestone as intentional, premium UI

- **Priority**: Existing behaviour is stable enough from owner testing. Polish
  every screen's visual hierarchy, typography, spacing, action clarity and
  empty/loading states. Do not add features or reopen backend/playback/FPL logic
  except for a regression introduced by UI work.
- **Evidence**: The app-wide presentation batch passes usability/FPL trust suites,
  generic iOS Release compilation and four Catalyst large-text audits. This is
  regression evidence, not per-screen physical visual acceptance. No deployment.

## 2026-09-08: Extend the calm UI direction across native browsing

- **Decision**: App-wide presentation consistency, preserving all functional
  destinations and trust labels rather than literally copying sample FPL data.
- **Implementation**: Circular All sports/Rugby equipment correction; grouped
  Matchday with simple header; readable shared fixture rows; underlined FPL
  workspaces and responsive tool rows; calmer manager/Coach headers; grouped
  search and sentence-case Settings headings. Shared semantic typography retains
  Dynamic Type. Existing player gestures and lifecycle remain untouched.
- **Boundary**: Local source batch only. Build 86 remains installed and TestFlight
  stays 81. Individual tool/iPad/appearance acceptance is not inferred from unit
  tests. Screen matrix: `docs/audit/Fotty-Appwide-UI-2026-09-08.md`.

## 2026-09-08: Install and physically inspect UI build 86

- **Evidence**: Signed Release/signatures, CoreDevice install/version and launch
  pass on Jelani's iPhone. Actual mirrored Home/Settings/Notifications, cricket
  filtering and sports sheet checks pass. Restored All sports; no toggles changed.
- **Finding/boundary**: Rugby artwork still shares American football's mapping.
  Light mode, large text and playback were not tested in this pass. No TestFlight
  upload or other-device install. Owned output cleaned; see release 86.

## 2026-09-08: Match Home equipment artwork to the approved preview

- **Decision**: Use native full-colour equipment emoji on Home sport tiles,
  matching the concept's football, cricket bat/ball, basketball, baseball and
  tennis artwork. Keep the All sports grid and unknown-sport symbol fallback.
- **Implementation**: SportEmblem has an opt-in illustrated-equipment mode;
  other surfaces retain their SF Symbols. Existing selection motion respects
  Reduce Motion. No downloaded assets, team-badge changes or added network work.
- **Boundary**: Local source change, not installed or uploaded. Actual rendering
  follows the device OS emoji artwork. Focused test status is in Current-State.

## 2026-09-08: Restore visual emphasis instead of shrinking all Home content

- **Decision**: Apply the owner's preview comparison: larger wordmark/team
  typography, better tile insets, competition labels without redundant sport
  prefixes, accent-coloured reminders and a uniform bottom navigation surface.
- **Implementation**: Home badges opt out of coloured outlines while retaining
  their contrast surface, cached sources and initials fallback. Team names wrap
  rather than forcing ordinary text to one line. Keep Sports/Search/Watch 2
  reachable; remove the competing Watch 2 container, not the feature.
- **Boundary**: No fixture classification, playback, score, reminder policy or
  preference change. Source work only; owner build 85 and TestFlight 81 unchanged.
  Verification status is tracked in Current-State; visual acceptance remains open.

## 2026-09-08: Install Settings UI as private owner build 85

- **Decision**: Update Jelani's iPhone in place for the requested UI test, without
  uploading to TestFlight or installing on another device.
- **Evidence**: Signed optimized Release build, strict signatures and CoreDevice
  installation pass. Launch denied by the device lock; owner acceptance pending.
  Temporary build output cleaned. See `docs/releases/Fotty-2.0.0-85.md`.

## 2026-09-08: Continue the calm UI direction with grouped Settings

- **Decision**: Keep Settings' main page focused on destinations, with match
  notification switches and FPL reminder access together on a Notifications page.
  Preserve existing preference keys, source controls, privacy disclosures and
  explicit system-permission opt-in.
- **Implementation**: Rename the interests entry to Home interests, expose
  Backup & restore directly, remove the decorative pitch background and bound
  the content width on iPad. Refresh actual notification permission on foreground;
  distinguish quiet/temporary delivery from full authorization.
- **Boundary**: Local source work only; build 84 remains the owner-device build
  and TestFlight remains 81. Wider FPL/Matchday layout changes are still separate.
  Catalyst app/test compilation succeeded; automation initialization timed out
  before execution, including the single retry. The three requested navigation,
  large-text and support checks are not claimed as passed. Owned output cleaned.

## 2026-09-08: Correct the native Home density after build 82 was visually rejected

- **Finding**: The owner screenshot did not match the compact concept. The
  shared `fottyScaled` helper maps numerical sizes to semantic system styles;
  changing its numerical argument within one bucket cannot reduce the font.
  Tall reserved title lines and a separate sports-overflow row also remained.
- **Decision**: Use Home-scoped `ScaledMetric` sizes for compact tile, interests,
  team and wordmark typography without changing the app-wide semantic helper.
  Keep equal measured tiles and Dynamic Type, reduce equipment/badge sizes,
  remove reserved empty title lines, and move phone overflow into the header.
  Do not offer that extra action on iPad where all sports are already shown.
- **Verification**: The focused usability suite passes, including a native
  rendered 361-point phone grid budget of at most 190 points at standard text
  size. Large-text and clipping UI audits pass. Navigation initially exposed
  redundant iPad overflow; the corrected navigation journey passes.
- **Boundary**: This corrects native Home/shared discovery density, not the
  broader FPL/Settings concepts or the separately reported U19 classification.
  Real phone comparison must be recorded separately from automated checks.
- **Physical follow-through**: Intermediate build 83 exposed four columns on
  Pro Max. Build 84 caps phones at three and adds a 398-point-width regression;
  signed build/install/launch and actual mirrored Home, overflow and cricket
  filtering checks pass on Jelani's iPhone. Restored All sports. Owner visual
  acceptance remains pending, and TestFlight stays 81. See the build-84 record.

## 2026-09-08: Install calm-Home UI as private owner build 82

- **Decision**: Use a distinct build number for the requested iPhone acceptance
  check without notifying the TestFlight group.
- **Evidence**: Signed optimized Release build and strict signatures pass;
  CoreDevice confirms 2.0.0 (82) installed on Jelani's iPhone. Automatic launch
  was denied because the device was locked. Owner acceptance remains pending.
- **Boundary**: In-place install only, no uninstall/data reset or other device.
  TestFlight remains 81. Owned build products cleaned on exit. See
  `docs/releases/Fotty-2.0.0-82.md`.

## 2026-09-08: Make routine Home UI quieter without concealing stale data

- **Decision**: Implement the first UI batch locally and preview broader screen
  changes before applying them. Preserve badges, equal sport choices, side Watch
  actions, opt-in reminders, interests and source-freshness rules.
- **Implementation**: Compact the masthead/interests/shared match rows. Scope
  CPL warnings to the events displayed in Home, Search and My Matchday; avoid
  stacking football and catalog notices. Move check timestamps behind a
  separately accessible Update details control. Healthy listings need no banner,
  while failed, stale and partial updates retain actionable warnings.
- **Testing policy**: Do not suppress notices during automated UI tests. Seed
  explicit fresh/stale/offline/partial states instead. The notice container must
  contain, not overwrite, child control accessibility identities.
- **Boundary**: Build 81 remains the distributed baseline. No install, upload,
  version change or broader FPL/Settings redesign in this batch. An interactive
  sample-data concept covers the next UI discussion, not actual live fixtures.
- **Evidence**: Six focused Catalyst UI journeys, catalog/usability unit tests,
  and the final unsigned generic-iOS Release compile pass. See
  `docs/audit/Fotty-Calmer-Home-UI-2026-09-08.md`; physical acceptance is pending.

## 2026-09-07: Release one reproducible build-81 reliability candidate

- **Decision**: Reconcile the current product graph against clean remote
  ancestry, close the FPL duplicate-replacement defect, qualify it without a
  simulator, and distribute one internal-only build rather than another direct
  device binary.
- **Implementation**: Reject unchanged/already-selected FPL elements with
  accessible feedback, isolate deterministic UI fixtures from production
  manager freshness, and add stable identifiers plus failure-only release
  evidence for Home, match-start and squad journeys.
- **Evidence**: Exact replay and Gitleaks pass; 22 memory tests, the complete
  public-Xcode 26.6 simulator-free policy/unit/Release gate and all 20 Xcode 27
  Catalyst UI journeys pass. The 2.0.0 (81) app and extension archive versions,
  identifiers and strict signatures pass; Xcode upload, Apple processing,
  compliance, focused notes and assignment to the unchanged seven-person
  internal group are complete.
- **Boundary**: Build 80 remains rollback. Exact TestFlight iPhone/iPad behavior
  and decoded Champions League match-time playback remain open; no tester,
  role, external group, production Worker, device install or Git history changed.

## 2026-09-07: Bound instruction context and make local memory retrieval/export trustworthy

- **Decision**: Use Current-State.md plus relevant topic sections for onboarding;
  retain historical records without treating old release statements as current.
  Source-only and read-only work have explicit stop boundaries; no automatic
  device installation, publishing, or simulator/build work for memory changes.
- **Implementation**: The standard-library memory helper preserves PiP/FPL/UCL/
  CPL, ranks bounded sections, prefers the current summary, and labels history.
  Export redacts URL credentials, structured secrets and private keys, checks
  residual patterns, verifies source digests and atomically replaces the last
  good bundle. Clipboard copying is opt-in. Health reports its limited checks.
- **Cross-project scope**: Codex gets shared Mac limits. Cursor continuity now
  separates project notes from explicit confirmed global preferences, rejects
  automatic assistant summaries as authority, and rebuilds per-workspace briefs.
  OtakuVerse's old homelab runbook is archived rather than active.
- **Verification/boundary**: Offline synthetic tests cover retrieval, redaction,
  failed exports, scope isolation and confirmation. No app build, version change,
  device install, TestFlight upload, production request or credential rotation.
  See `docs/audit/Instruction-Workflow-Repair-2026-09-07.md` for final checks.

## 2026-09-07: Join Champions League schedule truth to provider availability without inventing Watch

- **Finding**: The official 144-fixture feed was complete, but 17 formal club
  names were not exact reviewed aliases. Provider-only Home could omit an
  official fixture until a stream listing appeared, while different provider IDs
  could display the same match twice.
- **Decision**: Review all current official aliases; project source-free official
  Champions League rows into Home/Search/My Matchday; and merge cross-ID rows
  only on sport, exact kickoff and two reviewed whole-team identities. Prefer a
  source-backed representative and union only real provider descriptors.
- **Monitoring**: `tools/audit-ucl-readiness.mjs` compares the official window
  with three live catalogs and optionally resolves Worker variants. The daily
  provider workflow reports 72 hours; a dedicated workflow runs every 30
  minutes from 16:00–23:59 UTC on Tuesday–Thursday and Saturday, failing when a
  fixture is inside 30 minutes through three hours after kickoff without a
  usable source. Worker-generated Legacy fallback URLs are not usable evidence;
  Admin/PPV is included because the real player supports it.
- **Evidence/boundary**: All 36 official team names resolve. Protected PR 21
  merged as `2f7c6a13`; its post-merge hosted run found all 18 Matchday 1
  fixtures with three concrete variants each. Build 80 passes the complete
  simulator-free suite, public-Xcode 26.6 signed Release compile, strict archive
  signing and Apple processing. The established no-listed-encryption answer and
  focused notes persisted, and App Store Connect independently shows Internal /
  Testing for only the unchanged seven-person `Fotty Internal Smoke` group.
  Build 79 remains the rollback. Live UCL score/minute and goal/full-time alert
  coverage remains off, and metadata resolution is not decoded-playback proof.

## 2026-09-06: Matchday rendering is a revision projection, not body-time catalog work

- **Finding**: My Matchday combined per-frame `SceneStorage` scroll writes with
  repeated full-catalog personalization, official-fixture matching, status,
  playback selection and live sort calculations during SwiftUI body evaluation.
  Root tab selection also animated the replacement of the complete screen tree.
- **Decision**: Remove absolute Matchday scroll persistence and root-tab
  replacement animation. Build a single no-animation presentation projection
  keyed by catalog, score, clock, saved-match and follow revisions. Each
  candidate resolves official state, relevance, row reason and playback action
  once; sections and sort order reuse those values.
- **Settings boundary**: Remove instructions that merely repeat a control or
  destination, including provider implementation versions. Preserve disclosure,
  permission recovery, data-loss, destructive-action and error copy.
- **Evidence/boundary**: The complete simulator-free policy suite, live provider
  identity audit and generic iOS Release compile pass. Signed build 79 installed
  on Jelani's iPhone and Jet iPad; automatic phone launch was denied because it
  was locked, while iPad install and launch succeeded. Public Xcode 26.6 then
  archived and uploaded the internal-only candidate. Apple processed it, the
  established no-listed-encryption declaration was saved, and build 79 is
  Testing for the unchanged seven-person `Fotty Internal Smoke` group. No
  external group, tester or role changed. Hands-on acceptance remains open.

## 2026-09-06: Track the real WebKit owner before suspending background playback

- **Finding**: Device AVKit/WebKit logs from rejected build 77 show the provider
  HTML video entered WebKit-owned PiP and was playing. Fotty then received scene
  background and invoked its own suspension JavaScript; AVKit immediately
  changed the Web player to paused. The prior native-item diagnosis was not the
  playback path used by this cricket reproduction.
- **Decision**: Report standard and prefixed PiP events only for the confirmed
  owning web video. Give the scene transition 750 ms for that event, cancel web
  suspension when PiP is active, and cancel/reject native handoff while WebKit
  PiP or background owns playback. Preserve ordinary non-PiP suspension and
  same-attempt foreground recovery.
- **Evidence/boundary**: Executed JavaScript and bridge tests cover PiP state,
  owner-document scoping and deduplication; lifecycle tests cover the background
  race, ordinary suspension and handoff exclusion. The complete simulator-free
  unit/Release gate passes. Signed private build 78 is installed only on Jelani's
  iPhone; the owner repeated the previously failing provider PiP path and
  confirmed it is fixed. Build 78 is the accepted private baseline. TestFlight
  remains 75.

## 2026-09-06: Let AVKit own native PiP background transitions

- **Finding**: Internal TestFlight build 75 could display a native cricket PiP
  window on Jelani's iPhone yet leave its player paused; the PiP Play control did
  not recover until Fotty foregrounded. Scene background could win a race with
  the AVKit active callback, and system player-state changes were not observed.
- **Decision**: Preserve a playing PiP-capable native item across that callback
  race, explicitly pause only after PiP stop/failure/availability loss, and
  observe `AVPlayer.timeControlStatus` so system PiP Play/Pause remains aligned
  with Fotty and Now Playing. Keep the same player, item, proxy and attempt.
- **Evidence/boundary**: Four focused lifecycle regressions, the complete
  simulator-free unit/Release gate and ten selected Catalyst UI checks pass.
  Private optimized build 76 installed in place and launched only on Jelani's
  iPhone, but real testing rejected it: the native cricket item still could not
  resume from the system PiP Play control while Fotty remained backgrounded.
  TestFlight remains build 75 and build 76 must not be promoted. The next gate
  must exercise the paused live-network path, not only callback ordering.

## 2026-09-06: Make visible copy earn its space

- **Decision**: Primary surfaces retain only state, action, recovery and material
  privacy/correctness boundaries. Remove repeated explanations and replace
  implementation vocabulary such as catalog, endpoint, API allowance, cache,
  snapshot and playback handshake with user language.
- **Scope**: Home, Search, My Matchday, Match Hub, player states, Settings and all
  FPL workspaces were reviewed. Detailed teaching remains in Help; accessibility
  labels and consent/destructive/correctness warnings remain explicit.
- **Evidence/boundary**: Long direct visible labels fell from 64 audit candidates
  to 29. Complete simulator-free unit/Release and ten focused Catalyst UI gates
  pass. This stabilizes English copy but does not yet migrate localization, install
  a build or upload TestFlight.

## 2026-09-06: Make saved CPL interests immediately visible and remove repeated Home timing copy

- **Decision**: Competition toggles from the interests editor mutate and save
  through the same SwiftData `ModelContext` that powers its `@Query` views.
  Durable writes in an isolated context remain available for non-UI workflows,
  but the editor must not return Home to a stale interest snapshot.
- **CPL identity**: Every internally verified `cpl-2026-*` schedule row belongs
  to a saved CPL interest, including knockout placeholders whose teams are not
  known yet. Untrusted provider/editorial rows still require two reviewed CPL
  teams, and generic cricket channels remain outside the competition filter.
- **UI**: Remove the permanent Home timing/source disclaimer and repeated CPL
  schedule explainer. A current schedule-only CPL row displays its scheduled
  time inside the already-labeled live section instead of repeating `On now ·
  listed start`; broadcast caveats remain available where availability is
  actually explained.
- **Verification**: The exact 7:00 PM match 29 path is covered from saved CPL
  interest through the Home live section; all 39 schedule rows match CPL. The
  full simulator-free unit suite and generic iOS Release compile pass. No build
  was uploaded or installed.

## 2026-09-06: Activate fixture freshness and release the complete batch as internal build 75

- **Decision**: Ship the accumulated daily-use work as one significant internal
  TestFlight release rather than another direct-device patch. Keep the existing
  seven-person `Fotty Internal Smoke` group unchanged.
- **Activation**: Merge only the six fixture-monitor/Worker files through clean
  PR 17, deploy Worker version `e46fb1d9-06eb-4efb-8d24-ff5544e42215`, and run
  protected workflow 34056219335. Never publish the dirty old-ancestry checkout.
- **Release**: Allocate 2.0.0 (75) after confirming build 55 was Apple's latest.
  Public Xcode 26.6 full simulator-free gates, signed metadata/signatures and
  internal-only upload pass; Apple shows build 75 Testing for the one existing
  internal group with focused notes saved.
- **Boundary**: No direct install, new tester/role, external testing or App Store
  submission. Exact TestFlight installation and physical iPhone/iPad acceptance
  remain open. The reusable 8.52 GB arm64 iOS platform component was required by
  lightweight Xcode; every task-owned archive/result/log was removed.

## 2026-09-06: Never present retained fixture data as freshly verified

- **Decision**: Treat fixture revision, verification receipt, and broadcast
  catalog receipt as separate facts. Retained data may remain useful, but must
  not inherit the timestamp or authority of an unrelated successful refresh.
- **CPL**: Successful two-source verification always advances `checkedAt` while
  only content changes advance `revision`. iOS accepts only known source states,
  uses a two-hour freshness window, and will not replace a verified cache with a
  lower-trust fallback.
- **Football**: Keep football-data.org plus its 15-minute cache as PL/UCL schedule
  authority. A failed schedule refresh clears old analysis from official
  matching and produces a visible refresh notice; it does not remove the
  independently refreshed streaming catalog.
- **Monitoring**: Retain both CPL source audits and add daily full-season PL/CL
  contract validation. A monitoring failure is visible workflow evidence, never
  permission to publish partial data.
- **Boundary/evidence**: Live audits passed for 39 CPL, 380 PL and 144 CL rows;
  complete simulator-free iOS/Release, 136 web/Worker units, lint and Worker
  dry-run pass. The later build-75 decision above records activation and internal
  distribution; this entry preserves the implementation-time boundary.

## 2026-09-06: Give personalized Home a bounded three-day lookahead in build 74

- **Decision**: When the Home-only interest switch is active, show selected live
  events and the next 72 hours of selected fixtures chronologically, capped at
  three upcoming rows on iPhone and four on iPad.
- **Scope boundary**: Increase shared catalog retention to 72 hours so the view
  has data, but preserve broad Home's six-hour featured window, two-row later
  cap and explicit 48-hour later boundary. Full lineup and Search remain escape
  routes; no separate fixture feed or official-schedule claim is introduced.
- **Why**: Build 73's filter worked on hardware, but a one-day-only visible set
  can make a user's intentionally narrow Home feel empty between matchdays.
- **Verification**: Final simulator-free tests and generic Release pass. Signed
  optimized 2.0.0 (74) installed/launched only on Jet iPad; CoreDevice reports
  the exact build and a screenshot shows the active interest state plus
  `Next 3 days`. iPhone 70 and TestFlight 55 are unchanged.

## 2026-09-06: Make Home curation user-controlled in private build 73

- **Decision**: Reuse favorite teams and reviewed competition follows as one
  interest model. Add an opt-in `Only show my interests on Home` preference and
  one compact Home editor; do not create a second favorites database.
- **Safe default**: Existing users keep the broad catalog until they opt in. An
  empty or unavailable interest set fails open and disables the persisted
  restriction where observed, so preference loss cannot masquerade as an empty
  provider catalog.
- **Escape and alert boundary**: Full lineup and Search retain the complete
  catalog. Following a competition affects Home/Matchday relevance only and
  never opts the user into reminders or notifications.
- **Portability**: The encrypted private backup stores the switch as an optional
  version-one field; older backups decode and restore to broad Home.
- **Evidence**: Final simulator-free units and generic iOS Release pass. Signed
  optimized 2.0.0 (73) installed/launched only on Jet iPad and visually shows
  the truthful broad-Home state after upgrade. Hands-on selection/filtering and
  accessibility remain open. iPhone 70 and TestFlight 55 are unchanged.

## 2026-09-06: Bound Home prominence by audience relevance in private build 72

- **Decision**: Show at most three featured live rows on compact phones and
  four on iPad. Rank followed PL/UCL, Premier League, Champions League and
  CPL/explicit interests ahead of unrelated lower-priority listings. Keep every
  remaining live event in a counted `More live` disclosure and Full lineup.
- **Boundary**: This is presentation ranking only. It cannot invent importance
  metadata, change competition identity, hide events from the catalog, claim a
  score is live or prove a stream will decode.
- **Diagnostic correction**: Build 71's iPad capture exposed duplicate
  Alaves/Deportivo Alavés rows. Build 72 merges only exact reviewed aliases at
  the same sport and kickoff, preserving real sources and rejecting fuzzy name
  similarity as identity.
- **Verification**: The full simulator-free tests and generic iOS Release pass.
  CoreDevice reports signed optimized 2.0.0 (72) on Jet iPad; the duplicate is
  visually absent and the normal process survives 60 seconds. Hands-on More-live,
  scroll/rotation, real-PL ordering and media/accessibility checks remain open.
  Jelani's iPhone 70 and TestFlight 55 are unchanged.

## 2026-09-06: Refresh Stephon Antoine's internal TestFlight access

- **Finding**: The accepted App Store Connect account
  `stephonmantoine@gmail.com` was already in `Fotty Internal Smoke`, but Apple
  showed `No Builds Available` even though build 2.0.0 (55) was active,
  assigned to the group and due to expire in 88 days.
- **Decision/implementation**: Remove only that account's stale membership from
  the internal group and immediately add the same accepted account back. Keep
  its Marketing role, App Store Connect access, every other tester, all builds
  and external distribution unchanged.
- **Verification**: Apple confirmed `1 tester has been added to this group`, the
  group returned to six testers and Stephon's status changed to `Invited`.
  Installation and physical acceptance remain Stephon's next steps.
- **Sharp edge**: A separate misspelled pending user,
  `steponmantoine@gmail.com`, still exists in Users and Access. Do not confuse
  it with the accepted tester or resend it as the working account.

## 2026-09-06: Reject build 68 and cancel cold-scroll work at its real owners

- **Evidence**: The owner still saw Home stutter on the optimized build 68.
  Instruments and syslog could not attach because Xcode's beta device service
  treated the otherwise connected iOS 27 phone as offline, so the render path
  was audited directly rather than inventing trace evidence.
- **Correction**: Restrict catalog-wide CPL fallback to source-less CPL rows;
  reference-count badge waiters and cancel an underlying load when no visible
  row needs it; honor a 24-hour persisted badge-catalog freshness window; parse
  remote league catalogs outside MainActor; remove regex compilation from badge
  normalization.
- **Evidence**: Full simulator-free tests and generic iOS Release pass. Signed,
  optimized 2.0.0 (69) installs/launches on Jelani's iPhone and survives the
  process hold. Temporary output is removed and about 63 GiB remains free.
- **Boundary**: Physical cold-scroll acceptance of 69 is pending. Build 68 is
  superseded. Jet iPad and TestFlight 55 remain unchanged.

## 2026-09-06: Make catalog performance an owned, measurable system in build 68

- **Decision**: Keep catalog rows independent of global badge-service
  publication, publish the multi-league badge map atomically, coalesce and bound
  image work, cache Home projections by meaningful revisions and move complete
  SwiftData replacement to a model actor.
- **Measurement**: Keep coarse CatalogProjection/CatalogCacheReplace signposts
  and subscribe to MetricKit in real app runs. Retain only the latest hitch/hang
  scalars; never accumulate raw payloads or Instruments traces.
- **Workflow**: Performance validation uses a signed Release build on one
  explicit physical iPhone through `tools/ios-performance-gate.sh`. The script
  forbids target guessing, simulators and UI-test runners, uses one temporary
  build root, and removes it on success, failure or interruption.
- **Evidence**: Full simulator-free tests and generic iOS Release pass. The
  optimized 2.0.0 (68) app installed/launched on Jelani's iPhone and remained
  alive after 30 seconds. Disk returned to approximately 63 GiB free.
- **Boundary**: A cold-cache rapid Home/Full-lineup scroll remains required for
  perceived-performance acceptance. Jet iPad and TestFlight 55 are unchanged.

## 2026-09-06: Bound first-scroll catalog work in private build 67

- **Incident**: On iPhone, the first catalog gesture could freeze and stutter
  before later scrolling became smooth. Home eagerly created offscreen rows,
  wrote SceneStorage for every geometry change and decoded/animated arriving
  provider badges from the view task.
- **Correction**: Use lazy catalog stacks; capture offset without observation and
  persist only at scroll idle/disappear. Downsample badge bytes off the main actor
  to 256 pixels and publish dense badge loads without per-image transitions.
- **Verification**: The downsample and source-contract regressions, complete
  simulator-free policy suite, three-feed identity audit, signed Debug install
  and generic iOS Release build pass. CoreDevice reports 2.0.0 (67) installed on
  Jelani's iPhone.
- **Boundary**: The locked phone denied automatic launch, so process hold and
  physical first-scroll acceptance remain open. Jet iPad and TestFlight 55 are
  unchanged.

## 2026-09-06: Reject build 65 and replace comparator work with build 66

- **Incident**: Both owner devices opened and closed on build 65. Three device
  reports prove foreground scene-create `0x8BADF00D` watchdog terminations. The
  main thread was repeatedly performing catalog selection and club-name
  normalization from Home's sort comparator.
- **Correction**: Decorate every event with one precomputed presentation key,
  then sort only that key, kickoff and ID. Use attached supported-source metadata
  as the cheap availability signal; keep full broadcast matching tap-owned.
- **Verification**: A 40-event regression proves exactly one rank evaluation per
  item. The complete simulator-free policy suite, three-feed live identity and
  generic iOS Release pass. CoreDevice reports 2.0.0 (66) on the owner iPhone and
  iPad; both main app/extension pairs survive more than 65 seconds with no new
  crash report.
- **Boundary**: Build 65 is rejected and must not be distributed. Build 66 is an
  installed private candidate, not hands-on Home/playback acceptance. TestFlight
  remains 55 and no backend, provider, tester, production or paid state changed.

## 2026-09-06: Allocate and install private live-first build 65

- **Identity**: Allocate 2.0.0 (65) across the app and Live Activity extension
  so live-first discovery is never mistaken for accepted build 64.
- **Devices**: Build one signed universal Debug artifact and install/launch it
  on Jelani's iPhone 15 Pro Max and Jet iPad. Independent CoreDevice reads
  report Fotty Sports Hub 2.0.0 (65) on both.
- **Verification**: Generated competition data, five identity vectors, three
  reachable live feeds, the complete simulator-free policy suite and generic
  iOS Release build pass. The relevant Home Catalyst journey also passed before
  version allocation. Temporary build output was deleted; about 64 GiB remains.
- **Boundary**: This is private installation, not visual/playback acceptance or
  TestFlight distribution. TestFlight remains 55; no backend, provider, tester,
  paid-Coach, production or remote Git state changed.

## 2026-09-06: Never hide live matches behind Home's upcoming limit

- **Decision**: Home has a distinct Live now section containing every current
  live/listed-now event. The three-row cap applies only to upcoming discovery.
  Followed events lead live ordering, followed by Premier League, Champions
  League and the remaining competition tiers.
- **Why**: The redesigned Home sorted current events only by phase and kickoff,
  then kept three. A live Premier League match could therefore disappear behind
  See all after three earlier events, which violates the primary live-sports
  journey.
- **Provider copy**: The independent Score808 lane remains part of the bounded
  combined resolver, but its empty/error copy is provider-neutral. Provider
  identity remains available in attempt diagnostics and no longer implies that
  Score808 was the only route checked.
- **Verification**: The complete simulator-free policy suite and generic iOS
  Release build pass, including a regression proving five live rows are retained
  while five upcoming rows are capped at three. The focused Home Catalyst
  interaction journey passes. Temporary build output was deleted.
- **Boundary**: This is local source after private build 64. No device,
  TestFlight, production/provider, backend or tester state changed.

## 2026-09-06: Accept private iPhone web controls in build 64

- **Evidence**: Builds 61/62 still showed controls above a decoded provider feed
  without reliably owning physical touches. Build 63 proved the UIKit Sources
  action but exposed a second race: the preceding surface reveal tap allowed the
  provider's scripted restart to override Fotty Pause.
- **Correction**: Back only the compact Pause/Sources toolbar with UIKit buttons,
  leaving the rest of WebKit directly interactive. Clear any earlier trusted
  provider interaction when the app issues Pause; only a new provider tap may
  authorize provider Play.
- **Verification**: The complete simulator-free gate passes. On build 64 on
  Jelani's iPhone, a decoded stream held exactly at 76:05 for over 4.5 seconds,
  Fotty Play resumed, the provider's own Play resumed after a second pause, and
  Sources opened its selector. CoreDevice confirms 2.0.0 (64).
- **Boundary**: Jet iPad now runs and launches private build 64. Two physical UI
  attempts failed before a player opened, so they did not test controls; a known
  decoded stream and audible-close recheck remain. TestFlight remains 55; no
  backend, tester, production or paid state changed.

## 2026-09-06: Supersede private build 59 with playback-control build 61

- **Evidence**: Owner-device inspection reproduced a decoded web broadcast that
  continued after Fotty Pause; the visible label remained `Pause`. This is
  stronger than compile or mock evidence and keeps playback acceptance open.
- **Correction**: Keep web chrome out of hit-testing-disabled ancestry. Treat
  Fotty Pause as explicit intent against provider-script restarts, while a real
  provider surface interaction can still authorize Play.
- **Verification**: The executed monitor regression covers both programmatic
  restart rejection and genuine provider resume. The full simulator-free gate
  and generic Release build pass. One signed build 61 is installed and launched
  on the owner iPhone/iPad; CoreDevice confirms 2.0.0 (61) on both.
- **Boundary**: Installation is not exact-build playback acceptance. One quiet
  physical UI run returned an unidentified test failure; the diagnostic rerun
  then blocked on owner-device lock. All runner, result, diagnostic and build
  artifacts were removed. TestFlight remains 55 and no
  backend, tester, paid or production state changed.

## 2026-09-05: Allocate private build 59 for exact-device roadmap acceptance

- **Identity**: Allocate 2.0.0 (59) across app and Live Activity extension so
  the post-58 roadmap work is never mistaken for an earlier installed binary.
- **Devices**: Install one strictly signed universal Debug artifact on Jelani's
  iPhone and Jet iPad. Both launch and retain their main app/extension process
  pairs through 60 seconds; CoreDevice reads back 2.0.0 (59) on each.
- **Verification**: Exact final source passes 486 tests with two intentional
  skips, generic unsigned iOS Release, seven affected Catalyst UI journeys,
  three-feed live identity preflight and signed Release smoke.
- **Boundary**: This is a private cable candidate, not TestFlight or hands-on
  acceptance. Shared TestFlight stays 55; no backend, production, tester, remote
  Git or paid-Coach state changed. UI mirroring still needs owner authentication.

## 2026-09-05: Preserve daily context and make local recovery truthful

- **Browsing ownership**: Scene storage owns Home filters and Home/Search/
  Matchday positions. Existing shared catalog and FPL workspace owners remain;
  no new polling or duplicate feed is introduced.
- **Accessibility/theme**: Existing Settings controls reflow at accessibility
  sizes and use scaled typography. Secondary Playback Sources follows the chosen
  appearance; dark remains scoped to actual player/pitch presentation.
- **Persistence**: Publish Matchday mutations only after encode, write and
  readback verification. A failed removal cannot cancel a reminder. Refuse
  follows in SwiftData's volatile fallback rather than promising session-only
  state is saved.
- **Recovery/reporting**: Self-open every encrypted export before Files handoff.
  Restore Matchday before replacing follows and roll it back if the database
  replacement fails. Copy/share means prepared, never received.
- **Verification**: After unlock, 486 of 488 tests pass and two intentional
  live/soak tests skip; generic iOS Release and all seven affected Catalyst UI
  journeys pass. UI automation resets retained browsing defaults only once per
  DEBUG test process, so tests start independently while tab-return restoration
  remains under test. All owned build roots were removed.
- **Boundary**: Local batch only. Exact-device appearance/accessibility, Files
  recovery and received-feedback acceptance remain. No distribution, backend,
  version, production or paid action was taken.

## 2026-09-04: Bind the full FPL workspace to season, identity and evidence

- **Ownership**: Keep one primary refresh owner. A selected rival fetches only
  its published picks and uses the same accepted bootstrap/fixtures/live packet
  as the owner. Player histories have five-minute receipt checks, bounded selected
  requests and manager/player/season fences; errors retain labeled previous data.
- **Season safety**: Require explicit confirmation for legacy/restored or new-
  season manager IDs. Unknown unscoped drafts/chats cannot be safely attributed;
  preserve bytes without adoption or deletion. Check loaded season before reads,
  writes and async publication, not only when a screen opens.
- **Planning**: Use actual remaining calendar entries, official chip windows and
  reviewed 2025/26–2026/27 restrictions; unknown future rules fail closed. All
  wildcard entry points share the same qualified budget. Journals name their
  target gameweek and preserve the date of historical Coach evidence.
- **Coach**: Resolve explicit names against the complete current official catalog
  before shortlist reduction; clarify ambiguous/missing names before paid work.
  Bound history reads and user-context follow-ups. Optional structured transfers
  undergo complete-squad validation; never parse prose into executable moves or
  describe model confidence as measured accuracy. Public bank/selling values are
  estimates, and missing adjusted draft bank stays unknown.
- **Points**: Preserve raw official GW points and distinguish net contribution
  after transfer hits. Do not subtract hits twice from a computed net fallback.
- **Boundary**: Local batch only. Evidence and outstanding checks are in the FPL
  workspace implementation record. No deployment, paid request or distribution.
- **Verification**: 481 native tests passed, zero failures, two intentional
  live/soak skips; unsigned generic iOS Release, 135 web/Worker tests and final
  Worker dry-run passed. Owned build/packaging output removed, about 30 GiB free.

## 2026-09-04: Connect discovery, personal Matchday and current playback

- **Direction**: Implement roadmap batch 2 without another redesign, new tabs,
  simulators, device installation or release. Home discovers; Matchday plans.
- **Playback**: Shared current-event policy chooses exact active sources first,
  then reviewed CPL Fox/Willow alternatives. Preserve one tap and honest channel
  provenance, not a claim about the channel's actual programme.
- **Evidence**: Typed catalog receipts distinguish empty, failed, partial and old
  checks. Keep conflict tombstones through partial collection. Discovery has fair
  bounded family opportunities and cancellation ownership, not reduced playback
  decode grace. Generic failures are attempt-local, not provider-wide penalties.
- **Personalization**: Canonical sport/team aliases and reviewed league selection
  drive Following. Isolated transactional migration preserves unrelated pending
  edits and exposes failure. Saved/reminder identity survives omissions and
  same-ID schedule changes without fuzzy cross-match merges.
- **Refresh**: Match Hub publishes one score/insights snapshot; cancellation fences
  late completion. Canonical routes survive API enrichment. Catalog-only hubs
  refresh actual source withdrawal instead of presenting a dead Refresh action.
- **Verification**: Runtime evidence and physical gaps are recorded in
  `docs/audit/Fotty-Connected-Sports-Journey-2026-09-04.md`. Production remains
  unchanged; the source-only Coach cap is still 50 with paid access disabled.

## 2026-09-04: Implement the first private-product foundation batch

- **Direction**: The owner approved the whole-product strategy, not only audit
  patches. `docs/FOTTY-PRODUCT-EXECUTION-PLAN.md` is the current sequence. Preserve
  private scope, badges, compact UI, distinct Home/Matchday and optional FPL.
- **First batch**: Harden the native relay with loopback/session admission,
  destination/redirect/credential scope and resource bounds. DNS preflight is not
  full rebinding protection. Preserve unfinished manager/season FPL transfers,
  expose changed-baseline conflicts, validate complete combined routes and clear
  replaced working state on backup restore.
- **Owner cost choice**: 50 paid Coach attempts per UTC day for the entire group.
  Deterministic/on-device answers do not count. Persist reservations before model
  work and never refund uncertain cancellation/failure charges automatically.
  This is a usage ceiling, not an exact invoice guarantee or per-tester allowance.
- **Private access**: Individual revocable bearer codes in device-only Keychain;
  only their digests in a Worker secret. Mandatory configuration, one global
  Durable Object and one cancellable deadline. This is not attestation. Checked-in
  paid flag remains disabled; production/code provisioning requires separate
  approval and an app-compatible rollout, never an unprotected rollback.
- **Evidence**: Full simulator-free Catalyst/iOS Release gate, 83 web/Worker tests,
  Worker dry-run and diff check pass. Owned output cleaned; about 31 GiB free.
  See the foundation implementation record for physical/production gaps.
- **Boundary**: No paid call, code generation/delivery, version bump, installation,
  upload, production change or Git publication. Build 58/TestFlight 55 do not
  contain this work. The broader roadmap remains unfinished.

## 2026-09-04: Record comprehensive product audit without changing the app

- **Request boundary**: The owner asked for a deep whole-app audit and overlooked
  ideas explained for a nondeveloper. This turn inspects and recommends; it does
  not approve implementation, new services, uploads, invitations or Git publication.
- **Record**: `docs/audit/Fotty-Whole-Product-Audit-2026-09-04.md` separates current
  strengths, source-level defects, unverified runtime/production conditions and
  ten optional improvements. It recommends Trust and Daily Use before expanding
  the beta or adding more tools, while preserving the current visual identity.
- **Evidence**: Four parallel source/test reviews, existing iPad visual reference,
  primary-product reference checks, 71 fresh passing web/Worker tests, passing
  offline catalog/identity/CPL checks and zero known npm advisory findings. The
  earlier 326-test Catalyst/Release result is reused explicitly, not claimed as
  a new run. No simulator, device, Xcode build or paid Coach call was used.
- **Limits**: No application/backend behavior changed. Prior five repairs remain
  local after build 58; TestFlight 55 and device installs are unchanged. Live
  playback, exact-candidate accessibility/restore, production access/billing and
  feedback receipt still require their separate acceptance evidence.

## 2026-09-04: Fix the first five reliability audit findings before adding features

- **Scope**: The owner approved the five priorities discussed after build 58: exact match admission, cancellable retries, selected-player media ownership, retained concrete alternatives and coherent FPL live refresh. No TestFlight, device/service deployment or Git publication was requested for this step.
- **Decision**: Fail closed on ambiguous identity instead of ranking a one-team match. Quarantine contradictory provider IDs in one source-less internal row and omit them from browsing. Preserve exact delivery URL/header identities under existing bounded lookup limits.
- **Lifecycle**: `LivePlayerViewModel` remains the single retry/attempt owner. WebKit preserves intentional pause/background state; known ad/hidden/ended/removed media cannot retain broadcast ownership. Native handoff needs selected-video or explicitly bound player-API evidence, not general network traffic. Unknown MSE players may remain web-only; this is not universal ad detection or PiP certification.
- **FPL**: One visible-workspace poller reuses the state owner/revision path, including planning/deadline and full-time/final transitions. All scoring inputs require bounded current provenance before automatic publication. Failed refreshes retain the complete prior snapshot/timestamps, with age-aware presentation. No official transfer writes or paid Coach calls are added.
- **Evidence**: Controlled owner/transport/JavaScript tests plus the simulator-free Catalyst and generic iOS Release gate; exact final results and physical limits are in `docs/audit/Fotty-Reliability-Fixes-2026-09-04.md`. The nine remaining audit findings are separate work.

## 2026-09-04: Implement exact direct-site Score808 discovery and audit system transitions

- **Decision**: Build 58 removes the unverified donor mapping and independently checks the owner's actual Score808 site's public calendar only during an explicit late-window football Watch. Exact canonical teams, kickoff/timezone, visibility, expiry and unique current page ownership are required. Published HTTPS destinations and redirects are bounded; original page/player context is preserved. No rolling stream URL, TLS bypass or proxy is introduced.
- **Implementation**: Pure `Score808SiteCatalog`, bounded `Score808SiteResolver` and attempt-local `StreamDiscoveryCoordinator`. Partial choices and actionable failures survive slow-lane cancellation; incomplete detailed logs remain a follow-up. Shared HTML checks now consume the requested 8 KiB, without calling generic HTML proof of playback. Direct-site monitoring accepts only the observed main player and is reinstalled before every source/attempt load.
- **Verification**: Real production resolver returned the exact supplied Watch page during the reported fixture. Final simulator-free Catalyst suite: 273 passed, zero failures, two intentional skips after the live window closed; generic iOS Release and signed Debug builds pass. Final review caught a reused-web-view provider-mode bug, fixed with both-direction regression coverage. See `docs/releases/Fotty-2.0.0-58.md` for exact installation and remaining physical acceptance.
- **Audit**: `docs/audit/Fotty-Deep-App-Audit-2026-09-04.md` ranks 14 separate findings. Next recommended work is shared match identity, retry ownership, retained alternatives/media ownership, then coherent FPL/catalog snapshots. These are recommendations, not silently implemented changes or device-reproduced failures. No TestFlight, Worker/web deployment, Git publication or other device is authorized by this focused fix.

## 2026-09-04: Correct Score808 discovery claims using the owner's exact page

- **Evidence**: The supplied Score808 page decoded 852 × 480 football video in the browser through a different media host. Its public calendar explicitly maps the selected teams and kickoff to that page. It includes old events and reuses Watch URLs, so a generic article URL must not become a permanent per-match fallback.
- **Correction**: The following build-57 entry is historical implementation evidence, not a valid discovery contract. Copying an `admin` ID into `hotel` was unverified; its HTML validator does not reject the documented stubs. A sequential timeout can also erase earlier failure evidence. The prior certificate-only explanation cannot be applied to this direct site.
- **Next boundary**: Remove donor guessing, implement date/identity-checked direct-site discovery with bounded trusted destinations, and test actual player/context behavior before a new private build. No app source or deployment changed in this diagnostic turn. See `docs/audit/Fotty-Score808-Route-Investigation-2026-09-04.md`.

## 2026-09-04: Re-check and validate Score808 only in its late availability window

- **Finding**: Score808 commonly publishes its player only around 20 minutes before kickoff. Ipswich Town–Liverpool appeared identically in all three current catalogs with `admin`, `delta`, `echo` and `golf`, but no `hotel`, so Fotty never attempted Score808. A bounded diagnostic found the maintained `hotel` route with the event's `admin` identifier returned a full player page, while the other event identifiers returned only empty stubs. The Watch resolver also returned any cached event with some sources immediately, preventing a deliberate late-provider refresh.
- **Decision/implementation**: Treat Score808 as late-bound. From 30 minutes before a football kickoff through three hours after, an explicit Watch resolution refreshes provider metadata even if the cached row already has another source. When `hotel` remains missing, infer exactly one `hotel` descriptor from a non-empty `admin` identifier, probe only stream 1 and pass it through the existing page validator. Do not show an early/dead Score808 row, infer from `delta`/`echo`/`golf`, duplicate an explicit `hotel`, weaken TLS, or create background stream traffic. If the refresh fails, preserve the cached event and continue the same bounded validation path.
- **Evidence**: New regressions prove the 30-minute boundary, football-only scope, three-hour tail, explicit-provider deduplication and refusal to guess without `admin`. The complete simulator-free Catalyst unit and generic iOS Release gate passes. The signed-device run repeats generated-catalog and three-feed identity checks. CoreDevice independently reports Fotty Sports Hub 2.0.0 (57) on Jet iPad with the app and Live Activity extension running; owned build output is removed.
- **Boundary**: Build 57 is installed only on Jet iPad for private testing; TestFlight remains build 55. `embed.st` still has an expired certificate, so valid discovery cannot make the current route safe to load until the provider repairs TLS. No iPhone, other iPad, tester group, service, App Store submission or Git publication changed. See `docs/releases/Fotty-2.0.0-57.md`.

## 2026-09-04: Preserve provider security failures instead of reporting an empty stream catalog

- **Finding**: During the live Ipswich Town–Liverpool fixture, every current catalog feed carried the exact event with four descriptors and the two StreamEx APIs returned 12 concrete variants. All variants pointed to `embed.st`; its Let's Encrypt certificate had expired at 2026-09-04 14:59:58 UTC. Apple networking independently rejected the real URL with `NSURLErrorDomain -1202`. The resolver validated each candidate but then discarded those concrete failures when no session survived, and three single-match entry points discarded the final failure message, reducing a provider trust outage to an unexplained Retry/no-stream result.
- **Decision/implementation**: Never bypass ATS, accept an invalid certificate, rewrite playback to HTTP or restore a first-party stream proxy. Classify server certificate/trust and secure-connection errors as `provider_security_failure`, including the `NSError` form Foundation produced in the live check. Preserve the most actionable candidate failure when every embed fails and surface its safe user message consistently from Home, Arena and Match Hub. Continue consuming provider-supplied concrete embed URLs dynamically, so a renewed certificate or changed valid host can recover without a rebuild.
- **Evidence**: New regressions cover expired-certificate classification, the Foundation `NSError` bridge, ordinary timeouts and failure precedence. The complete simulator-free Catalyst unit and generic iOS Release gate passes after the final bridge correction. The signed-device run repeated generated-catalog and three-feed identity checks; CoreDevice independently reports Fotty Sports Hub 2.0.0 (56) on Jet iPad with the app and Live Activity extension running. Temporary build output was removed.
- **Boundary**: This fixes diagnosis and recovery semantics, not the provider's certificate. Current playback remains unavailable while every supplied host fails trust. Build 56 is installed only on Jet iPad for private testing; TestFlight remains build 55. No iPhone, other iPad, tester group, Worker, web deployment, Git commit or publication changed. See `docs/releases/Fotty-2.0.0-56.md`.

## 2026-09-04: Add accepted users to the internal TestFlight group as a separate step

- **Finding**: App Store Connect account acceptance does not automatically grant TestFlight group membership. `Fotty Internal Smoke` still had three testers even though Jhamol and Kirby/Rhys had accepted their team invitations. Akielle remained marked `Resend Invitation` and therefore was not selectable as an internal tester.
- **Decision/evidence**: After explicit owner confirmation at the final access-change action, add Jhamol Clarke and Rhys Benjamin to the existing internal group only. Apple confirmed two testers added; the group now has five testers and both new rows show Internal / Invited. After separate owner confirmation, resend Akielle Jackson's App Store Connect invitation; Apple confirmed `Invitation Resent`.
- **Boundary**: Akielle must complete the newest account invitation before TestFlight membership can be added. No role, app scope, build assignment, external group or public distribution changed.

## 2026-09-03: Use Fotty Sports Hub as the public name without migrating technical identity

- **Product decision**: The owner approved **Fotty Sports Hub** because the product now covers multiple sports, while retaining the accepted F-over-pitch icon and `FOTTY` wordmark. Use `Fotty` naturally in ordinary copy; use the full name for installed-product and primary metadata identity, with `SPORTS HUB` as a subordinate visual descriptor.
- **Implementation**: Add one iOS brand contract, set app/extension display names, expose the descriptor in Home and the full name in Settings, and update the PWA manifest plus primary web metadata/navigation identity. Preserve bundle IDs, Xcode target/scheme/module names, deep links, storage keys, private-backup identifiers, service routes and signing so installed data and integrations do not migrate.
- **Version/evidence**: Allocate 2.0.0 (55) because TestFlight build 54 is already distributed. Apple plists/JSON and spelling checks pass; web/Worker units pass 71/71, lint and production build pass; the complete simulator-free Catalyst unit/generic iOS Release gate passes. The current identity audit passes across three feeds. Xcode 26.6 (`17F113`) archives the normal generic-device Release with two jobs; app/extension both report 2.0.0 (55), the new display name and valid strict signatures. The signed app executable SHA-256 is `78b66698e84faf600802ff854c8c695c30aa678397007014b7e45d257685f3f9`. Apple processed the accepted internal-only upload, saved the built-in-encryption declaration and focused English (U.K.) notes, and shows build 55 as Internal / Testing for only Fotty Internal Smoke with its three testers.
- **Tester access/boundary**: At the owner's direction, invite Jhamol Clarke (`jhamol61@gmail.com`) with the Marketing role, Fotty Sports Hub as the only selected app and Create Apps disabled. Apple confirms the invitation was sent. It is pending App Store Connect acceptance and is not internal TestFlight group membership; the existing group remains at three testers. No direct device install, external group, App Store submission, web/Worker deployment, Git publication or physical acceptance occurred. Exact build-55 installation, retained-data checks, iPhone/iPad layout and live playback/PiP acceptance remain open. All disposable archive/export/DerivedData/distribution-log output was removed; disk remains approximately 32 GiB free.

## 2026-09-03: Promote the accepted one-tap CPL correction as internal TestFlight build 54

- **Authority/scope**: The owner explicitly approved a TestFlight update and invitations for `akiellejackson@gmail.com` and `kirbybenjamin1996@gmail.com`. Allocate build 54 because builds 52 and 53 were already physically distributed; do not reuse them. Keep the rollout internal-only, reuse only `Fotty Internal Smoke`, and do not install directly on a device or open external testing.
- **Release evidence**: Current generated-catalog and three-feed identity checks pass. Xcode 26.6 archived the normal generic-device Release with two jobs; app and extension both report 2.0.0 (54), minimum iOS 26.4, expected bundle identifiers and a strict valid signature. The signed app executable SHA-256 is `96d82accd1d0510d29c95c1709caf8f3877c9bed9472364c61efc4dff7b36d61`. Apple accepted and completed the internal-only upload. The unchanged built-in-encryption-only declaration and focused English (U.K.) notes are saved. Build detail shows only Fotty Internal Smoke, with three existing testers; a fresh group read reports nine builds and build 54 as Internal / Testing.
- **Access decision**: Send both new users the qualifying Marketing role with only Fotty selected in the one-app chooser and no Create Apps permission. They are pending App Store Connect invitations, not yet TestFlight group members; add them only after each accepts. Apple confirmed both invitations were sent.
- **Boundary/cleanup**: Build 53's owner acceptance covers the changed CPL behaviour, but exact build-54 TestFlight installation and feedback remain open. Email receipt and invitation acceptance are not inferred. All task-owned archive, DerivedData, export and distribution-log artifacts were deleted; free disk remains approximately 33 GiB. No simulator, direct install, external group, App Store submission, service deployment, commit or publication occurred.

## 2026-09-03: Use one-tap CPL channel fallback in private build 53 without inventing programme data

- **Finding**: CPL schedule rows and the generic Fox Cricket/Willow Cricket rows intentionally had separate identities. Exact team-and-kickoff matching prevented a channel source from being falsely attached to every CPL fixture, but it also left a currently scheduled CPL row saying no stream even when a playable cricket channel was listed elsewhere on the same screen.
- **Decision/implementation**: Preserve exact match-source matching as the preferred Watch path. For a CPL fixture with no exact active source, from two minutes before kickoff through eight hours after it, expose one `Watch` action across Home, the full schedule and Search. One tap opens Fox Cricket when active; Willow remains a separate channel row. A passed trusted CPL kickoff counts as `On now · listed start`, not an official live claim. Build 52's intermediate options sheet and second tap were rejected during physical use and removed immediately.
- **Verification**: Focused policies cover supported/retired sources, CPL identity, both availability-window edges, preferred-channel ordering, the listed-start activity summary and removal of the sheet. The complete simulator-free Catalyst unit/policy suite and generic iOS Release compile pass under Xcode 26.6 with two jobs. Private build 53 then passes live identity across three reachable feeds, signed Debug/generic Release compilation, strict signing and installation only on Jelani's iPhone. CoreDevice independently reports 2.0.0 (53) with the normal app and extension running. All owned temporary build roots were removed; free disk remains approximately 33 GiB.
- **Physical acceptance/boundary**: The owner confirmed during the current CPL window that build 53 no longer says tomorrow and opens the broadcast from the fixture with one tap and no intermediate sheet. This is time-scoped acceptance of the exact discovery/routing correction, not proof of permanent Fox/Willow programming or the remaining wider-beta gates. TestFlight remains build 51; build 52 is superseded. No iPad/other-phone change, upload, tester mutation, service deployment, commit or publication occurred.

## 2026-09-03: Release build 51 to the internal group and invite the CPL tester

- **Authority**: The owner explicitly approved publishing build 51's focused testing notes, assigning only the existing `Fotty Internal Smoke` group and adding `kevon.samuel32@gmail.com` as an internal tester. No external TestFlight/App Store submission, new group, device install, simulator, service deployment, paid call or Git publication was authorized or performed.
- **Access decision**: Kevon Samuel had already accepted App Store Connect and already held the qualifying Marketing role with app access. Preserve that role and do not broaden permissions. Add only that account to the existing internal group. Apple labels the scope `All Apps`, but its app chooser contains exactly one row—Fotty (`com.jelani.Fotty`)—selected; with only one account app, the UI cannot preserve a distinguishable one-app selection. Recheck and narrow this scope before a second app is added to the account.
- **Apple evidence**: App Store Connect confirmed one tester added. A fresh group read shows three testers and eight builds, with Kevon Samuel listed as Internal / Invited. A fresh iOS builds read shows 2.0.0 (51) Internal / Testing for Fotty Internal Smoke. The English (U.K.) notes are saved and cover discovery/badges, CPL fixture accuracy, playback/PiP, FPL, appearance/accessibility/backup and labelled TestFlight feedback.
- **Boundary**: Group availability and invitation state are proven. Email delivery, TestFlight installation, CPL playback, PiP/background continuity, FPL correctness and received feedback remain tester acceptance work.

## 2026-09-03: Use an Apple-supported public Xcode for TestFlight archives

- **Finding**: The installed Xcode 27 beta still built, signed and installed build 51 on the owner's beta-OS iPhone, but App Store Connect later rejected its otherwise valid internal delivery as an unsupported Xcode/SDK version. The Mac's supported Xcode 26.6 installation contained the iOS 26.5 SDK but did not expose a generic iOS destination or compile Fotty's assets until its matching platform runtime was installed.
- **Decision/implementation**: Keep the beta Xcode available for current beta-device work, but select the current Apple-supported public/RC Xcode explicitly for TestFlight. Verify `generic/platform=iOS` before archiving. Install only the matching Apple-silicon platform component when required; do not boot a simulator. Record its persistent disk cost separately from disposable release artifacts.
- **Evidence**: Apple lists Xcode 26.6 (`17F113`) as the current supported public release. After the 8.52 GB iOS 26.5 component was installed, the normal generic-device Release archive passed strict signing with matching app/extension 2.0.0 (51), minimum 26.4 and expected identifiers. Apple's internal-only upload returned `Upload succeeded` / `EXPORT SUCCEEDED` at 18:07 AST. Every task-owned archive, DerivedData/export root, failure result bundle and distribution log was removed; free disk is approximately 33 GiB.
- **Boundary**: Upload acceptance alone was not Apple processing, compliance completion, group assignment, installation or physical acceptance. App Store Connect later completed processing and build 51 is now Internal / Testing as recorded above. The component is retained because future supported uploads require it; no simulator process ran and no connected device changed.

## 2026-09-03: Activate independently refreshable CPL fixtures and fail closed on source conflict

- **Finding**: The app still bundled a schedule manually checked on 27 August and retained started CPL rows for 36 hours. Current verification also exposed a dangerous upstream disagreement: CPL and Wisden list Match 28 at 10:00 a.m. Guyana time, while Cricbuzz currently reports a start five hours later.
- **Decision/implementation**: Keep the official CPL announcement and explicit official corrections authoritative. The existing Worker dynamically compares those facts with Cricbuzz as a current independent verifier, returning an agreed update or a complete reviewed 39-match fallback. Validate every identity/time/stage before iOS caches it, preserve the newer last-known-good copy on failure, and retain the bundled schedule offline. A daily action may prepare a manifest PR when sources agree; it may not write directly to `main` or guess through a conflict. Retire started T20 rows after eight hours.
- **Evidence**: Structural and live three-source audits pass with the known Match 28 conflict surfaced; five focused CPL policy/route tests and the complete 71-test web/Worker suite pass with clean lint and Worker dry-run. The protected publication PR #16 passed repository, web, simulator-free iOS and CodeQL gates and merged at `d97140f`; manual monitor run `33764542003` then passed on `main`. Production health identifies source `2026-09-03.cpl-fixtures-3` / Cloudflare version `2b988894-e84a-45ac-b60f-23e2a8eac498`, and the route returns 39 fixtures with official Match 28 at 14:00 UTC. CoreDevice independently reports 2.0.0 (51) on Jelani's iPhone 15 Pro Max, launches the normal app and observes it for 60 seconds.
- **Boundary**: Runtime two-source agreement is labeled `live-verified`; the PR is the separate durable fallback review path. The repository keeps default read-only workflow permissions, while its Actions PR capability is enabled only so the pinned monitor can create that review PR; the workflow contains no approval or merge step. Build 51 is directly installed on the owner iPhone and its internal-only upload is Apple-accepted but still processing; neither path proves iPad, exact TestFlight availability or interaction acceptance. The 2026 data must never auto-roll into another season.

## 2026-09-01: Allocate build 50 for the connected iPhone 16e

- **Authority**: The owner explicitly requested installing Fotty on the connected iPhone 16e. This authorized pairing, device registration, a unique private build, installation and bounded launch verification on that device only—not TestFlight, another device, tester changes, service deployment, Git publication or automated UI interaction.
- **Version/provisioning decision**: Do not reuse private build 49 because current source contains later Graphify/FPL/playback changes. Allocate 2.0.0 (50) across app and Live Activity extension. When the generic Debug profile was rejected for omitting the newly paired phone, preserve the already-passing source and rebuild once against its actual UDID with automatic device registration; do not uninstall, weaken signing or alter another device.
- **Evidence**: The physical iPhone 16e is wired, unlocked, paired, on iOS 26.6 with Developer Mode enabled and had no existing Fotty install. Reference generation, live identity across three reachable feeds and the complete simulator-free Catalyst policy suite pass. Strict app signing and matching app/extension 2.0.0 (50) identity pass; CoreDevice independently reports build 50, launches the normal app and sees it for 60 seconds. The generic iOS Release graph also compiles, and all owned build roots are removed.
- **Boundary**: This proves installation and process health only. Exact-device UI, playback, PiP/background, notifications, FPL, accessibility and backup acceptance remain manual. Shared TestFlight remains build 48; any changed later candidate must be 51 or higher.

## 2026-08-31: Extract playback decisions without splitting playback ownership

- **Finding**: Graphify identified `LivePlayerViewModel` as the next production hotspot at 100 direct edges and 1,256 lines. Its AVPlayer, WebKit, proxy, attempt, task and PiP lifecycle must remain coordinated, but failure precedence and source classification were deterministic policy embedded inside that mutable owner. The file also retained an unused duplicate initial-selection method, logger and imports.
- **Decision/implementation**: Keep `LivePlayerViewModel` as the only mutable playback authority. Extract failure classification/state/value contracts, source-shape/health-ranked selection and a pure recovery decision table. The table preserves the established order: network loss keeps the same attempt; failed native handoff returns to the same web source; direct native startup may try its web form; a non-rejected web source receives one bounded stall/startup retry; source exhaustion and failover occur only after those options. The view model executes every side effect.
- **Evidence**: The view-model file falls to 1,154 lines and Graphify degree to 99. The final map has 383 files, 5,819 nodes and 15,129 clustered edges with an empty import-cycle section. Community count is deliberately excluded as a trend because repeated identical-source clustering yielded 235 and 251. Focused recovery/source policy tests and the existing attempt, pause/background, native-return, PiP and bridge contracts pass, followed by the complete simulator-free Catalyst unit and generic iOS Release gate.
- **Boundary**: Compilation cannot prove a current third-party stream decodes or system PiP survives app switching. Those remain exact-build physical acceptance. No version, device install, TestFlight upload, deployment, Git commit or publication was authorized or performed.

## 2026-08-31: Split FPL persistence and derived computation without splitting truth

- **Finding**: Graphify identified `FPLAdvisorViewModel` as the most connected production node at 154 edges. Its legitimate UI/request ownership was mixed with UserDefaults encoding/migration and a large pure derived-state calculation. Full load and live refresh paths also performed that calculation twice in immediate succession.
- **Decision/implementation**: Keep every observable property, request revision and mutation boundary on `FPLAdvisorViewModel`. Extract manager/season workspace storage into `FPLWorkspacePersistence` and pure validation/live/planning/command/optimizer computation into `FPLAdvisorDerivedStateBuilder`. Collapse load and live-refresh recomputation to one pass. Do not introduce child observable stores or competing sources of squad/scoring truth.
- **Evidence**: The view-model file falls from 1,405 to 1,318 lines. Its Graphify degree falls to 152; the full follow-up graph has 382 files, 5,794 nodes, 15,090 edges, 235 communities and no import cycle. Existing legacy-draft, relaunch, published/draft switching, scoring and stale-Coach tests pass in the focused suite, followed by the complete simulator-free Catalyst unit and generic iOS Release gate.
- **Boundary**: This is internal structure and repeated-work removal, not an FPL behavior or storage-format change. No version, install, upload, deployment, Git commit or publication was authorized or performed.

## 2026-08-31: Physically remove dead graphs and use Graphify as evidence, not authority

- **Authority/finding**: The owner selected dead-code removal and code optimization as the next milestone and specifically requested Graphify relationship analysis. The initial map contained 464 code files, 6,437 nodes, 16,886 edges and 291 communities. It confirmed no import cycles but exposed retired product islands and the real high-connectivity state owners.
- **Decision/implementation**: Keep only the iOS/Live Activity, companion sports web and Cloudflare Worker product graph. Delete the TWA/Android and homelab roots, the compile-isolated Hybrid P2P/Ace/warmup stack, disconnected web v1 surfaces, duplicate playback/session/token code and obsolete one-off browser probes. Narrow internal web exports. Do not delete from graph degree alone: preserve installed-store type metadata, P2P-shaped input rejection, the Live Activity compatibility field, dynamic service-worker registration, generated catalog contracts and Wrangler bindings.
- **Evidence**: The final Graphify map is 380 files, 5,769 nodes, 15,005 edges and 250 communities, again with no import cycles. Knip reports only the documented dynamic/generated/configuration exceptions. The complete simulator-free iOS gate, clean web lint, 66/66 web/Worker tests, production Next build and Worker dry-run pass.
- **Boundary**: The graph identifies `FPLAdvisorViewModel`, `LivePlayerViewModel`, `SportsDashboardView` and `MatchHubData` as the next refactor seams, not dead code. This work did not authorize or perform a version change, direct install, TestFlight upload, deployment, Git commit or publication.

## 2026-08-31: Adopt all five whole-app qualification recommendations

- **Authority/product direction**: The owner approved every recommendation in `docs/audit/Fotty-Whole-App-Readiness-Audit-2026-08-31.md`. Sports discovery and truthful playback are the universal promise; FPL remains a first-class optional module. Gameweek, Squad and Coach stay primary, Tools stays secondary, and each tool must expose whether it uses official facts/fixtures, projections, estimates, published data, an on-device plan or an advanced solver. Fotty never submits official FPL changes.
- **Active-graph cleanup**: Remove the unreachable community/chat/profile, old insights/highlights, mock-match, stream-debug and validation code from the production target. Remove the avatar/photo surface and photo-library permission because no non-social job remains. Retain the old SwiftData type metadata only as compatibility tombstones until a tested migration can prove existing private stores remain readable; this is not an active social product.
- **Trust boundaries**: Show a blocking persistence warning when the durable SwiftData store cannot open. Reconcile `PrivacyInfo.xcprivacy` to the actual transmitted boundary using Apple's current key/type names: public FPL User ID, installation Device ID and opt-in Coach Other User Content; local diagnostics are not automatically uploaded. Add a non-secret Worker `sourceVersion` to health, but treat it as local/source-only until an authorized deployment is read back.
- **Compatibility/qualification**: Keep iOS/iPadOS 26.4 as the intentional minimum for this private cycle. The next beta expansion is limited to 3–5 trusted testers completing the seven-day protocol in `docs/beta/PRIVATE-QUALIFICATION-2.0.md`. Exact-candidate physical PiP, backup/restore, live-stream recovery and accessibility checks are entry gates, not tasks to defer into a wider group.
- **Boundary**: This approval authorizes local implementation and simulator-free qualification. It does not authorize a version bump, device install, TestFlight upload, Worker/web deployment, tester/role mutation, paid-model call or Git publication.

## 2026-08-31: Use whole-app qualification, not feature count, for the next beta

- **Authority/finding**: The owner requested a deep audit of every system, screen and option and asked for the material questions before continuing. The resulting current authority is `docs/audit/Fotty-Whole-App-Readiness-Audit-2026-08-31.md`; older World Cup/Arena and build-33 completion reports are marked historical for current-status purposes.
- **Decision implemented now**: Treat build-49 source as owner/private pre-test quality, not wider-beta qualified. Preserve the existing TestFlight build 48 until one coherent milestone closes exact-build hardware, outsider-task, privacy and backend-version evidence. Fix the reproduced loaded-badge accessibility label and prevent intercepted stream URLs from entering Release logs; Debug logs retain only credential/query/fragment-free host/path information.
- **Verification**: The exact edited source passes `git diff --check`, the complete simulator-free iOS unit/policy and generic Release gate, 74/74 web/Worker tests, zero-error lint, Worker dry-run and production health. Badge gates pass 272/272 reviewed artwork URLs and 128/128 current live provider tokens. All task-owned DerivedData/result folders are deleted; no simulator, device install, upload, deployment, paid model call or Git publication occurred.
- **Decision status**: All five questions were subsequently approved and implemented locally; the entry above is the current authority.

## 2026-08-31: Treat live badge tokens and fallback catalogs as one reliability chain

- **Finding**: TestFlight build 48 sent opaque provider badge tokens through a corrupted decoded URL. Basketball's current catalog depends entirely on those tokens; current MLB listings often omit them and depend on bundled name lookups. Empty-provider Villarreal also exposed that valid ESPN results were not published until every optional catalog task finished.
- **Decision/implementation**: Correct the token endpoint, validate the exact current token set without retaining images, publish each completed league result immediately, retry a fully failed bootstrap after a two-minute cooldown and let the shared image loader fall through from bad explicit art to a known brand. Extend current football/MLB/American-football coverage and keep ambiguous rugby shorthand sport-scoped.
- **Evidence/boundary**: All 164 current provider tokens and the full simulator-free native gate pass. The owner stopped the shared archive before export/upload; build 48 remains newest in TestFlight. A separate signed Debug build installed in place only on Jelani's iPhone, where CoreDevice reports 2.0.0 (49) and a normal app/extension launch. The iPad, tester group, services and repository were unchanged.

## 2026-08-31: Use private pre-tests for small fixes and TestFlight for milestones

- **Direction**: Do not push every small bug fix to TestFlight. Install uniquely numbered, validated pre-test builds only on the owner's explicitly selected iPhone. Let several days of fixes and improvements accumulate, then use TestFlight only for a coherent significant change that warrants a new tester round and focused notes.
- **Release rule**: Time passing is not sufficient by itself; the batch must have meaningful user-visible scope or substantial reliability/quality value. Urgent blockers remain an explicit exception. A build number consumed by a physical private install cannot identify later changed source, so the next changed shared milestone after private build 49 must be 50 or higher.

## 2026-08-31: Make badge identity exact and motion contextual

- **Finding**: The shared UI could show a football loader while cricket or another sport was selected, several animations ran indefinitely without complete accessibility/power/lifecycle gates, and the badge bootstrap could fan out into per-team SportsDB requests. A live audit hit the provider's 25-request/two-minute throttle and its first permissive normalization cross-wired Paris FC with the `Paris` alias for Paris Saint-Germain.
- **Decision/implementation**: Keep one measured `TeamBadgeWindow` with a monogram fallback, exact source-controlled aliases and no fuzzy cross-club substitution. Bootstrap football artwork through bounded league-level ESPN metadata; reserve SportsDB for CPL/IPL/Argentinian basketball and one-off unresolved names. Add one sport motion profile used by Home selection, discovery/loading, stream resolution and player preparation. Continuous animation stops under Reduce Motion, Low Power Mode and inactive scenes; never cover playing video with decoration. Remove the obsolete user-facing P2P handshake/peers/chunks screen.
- **Evidence/boundaries**: The non-retaining live audit validates 272/272 image signatures across 148 source football names plus NBA/WNBA/MLB/NHL/CPL/IPL and proves all 13 shared URLs are aliases of the same club. Motion/badge regressions, the full Catalyst suite and a generic unsigned iOS Release pass without a simulator. A one-shot celebration primitive exists but is not connected to inferred events; only a verified goal/wicket/equivalent may trigger it. No build number, device install, TestFlight upload, server deployment or Git publication.

## 2026-08-30: Keep Fotty private and make recovery user-controlled

- **Authority/decision**: The owner explicitly decided Fotty stays private. The supported distribution paths are the existing invite-only internal TestFlight group and an explicitly authorized private cable build for a narrow device check. Public App Store submission and external TestFlight are not active goals; do not build review workarounds or widen access without a new explicit decision.
- **Implementation**: Add a versioned Private Backup workflow under Settings → Privacy & Local Data. A user-chosen password protects the file with AES-256-GCM and PBKDF2-HMAC-SHA256. The previewable payload covers preferences, follows, saved Matchday identity and manager-scoped local FPL plans. It deliberately excludes credentials, provider URLs/source identifiers, Coach conversations, AI consent, reminders, diagnostics and cached feeds. Restore validates the entire payload before mutation, replaces only the documented local state, clears consent and leaves reminders off.
- **Evidence/boundaries**: Four focused encryption/capture/restore/atomicity regressions and the complete simulator-free iOS CI gate pass, including provider identity vectors, all unit tests and generic unsigned iOS Release. The backup file type is registered as `.fottybackup`. No build number, device install, upload, deployment, paid call or tester change was made. Real Files-app export/import, wrong-password handling and restore on a physical device remain human acceptance.

## 2026-08-30: Remove retired product graphs after CodeQL exposed their residual risk

- **Finding**: The first advanced CodeQL pass on the clean GitHub baseline found 71 open alerts. The critical/high results were concentrated in code Fotty no longer operated: the Android prototype, Python homelab/P2P services, a same-origin embed proxy, PocketBase account/admin/billing routes, and movie/TV endpoints. Keeping those graphs made the repository's attack surface, workflow gates, documentation and maintenance burden materially larger than the supported product.
- **Decision/implementation**: Delete the retired Android and Python server trees rather than suppress their findings. Remove the dormant Next account, admin, billing, PocketBase, P2P-server, embed-proxy and movie/TV routes plus their tests, scripts and UI entry points. The supported web graph is guest-accessible sports discovery/playback with local preferences and reminders; the Cloudflare Worker owns the limited playback/football/Coach edge APIs. Pin every GitHub Action to an immutable commit, constrain service-worker messages and notification navigation to exact trusted origins, stop persisting credentials in browser storage, and replace remote homelab project-memory tooling with local repository scripts.
- **Boundary/evidence**: Historical decision entries remain history, not runnable architecture. Third-party player pages remain on their distinct provider origins and are not presented as first-party content. Swift CodeQL remains unavailable under the bounded Xcode 27 extraction attempt and is not claimed. Web units, TypeScript, lint, Worker dry-run, production build, workflow validation, gitleaks and protected pull-request gates passed. A fresh `main` scan after PR #10 reduced the inventory from 71 to two medium findings; PR #11 removed the network-to-file audit sink and made the test bridge origin check directly verifiable. The subsequent `main` Actions/JavaScript/Python CodeQL scan reports zero open alerts.

## 2026-08-30: Treat active native PiP as background playback, not foreground decoration

- **Finding**: On a real iPad, native handoff entered the system PiP window but playback paused as soon as another app opened. Fotty declared the audio background mode and retained its PiP controller, but set only the audio-session category, left `AVPlayer.audiovisualBackgroundPlaybackPolicy` on `.automatic`, and incorrectly marked an active PiP session for foreground resume.
- **Decision/implementation**: Activate the `.playback`/`.moviePlayback` audio session only when playback or PiP actually begins, set every direct and web-handoff native player to `.continuesIfPossible`, reassert both at the PiP/background boundary, and keep the active native state without arming foreground recovery. A stopped/failed PiP while backgrounded still pauses safely. The controller now acknowledges restoration to the still-mounted player UI.
- **Evidence/boundaries**: Add a unit regression proving active PiP remains `.playing(.native)`, retains its background policy and does not mark itself for resume after backgrounding. The full Catalyst suite and unsigned generic iOS Release pass without a simulator; protected PR #8 is merged to `main`. After explicit owner authorization, private build 47 was allocated with `tools/set-version.sh`; signed Debug product/version commit `e1b7f0d` was installed only on Jet iPad. Both app and Live Activity extension report 2.0.0 (47) with valid signatures, CoreDevice independently reports 47, and the app survived a 60-second physical process hold. The bounded build output was deleted. An earlier local 46 install was immediately superseded and is not acceptance evidence because it reused TestFlight's build number. Build 47 certifies installation/process health only; repeat with a native stream by opening another app for 60 seconds and locking/unlocking. No TestFlight upload, iPhone change or simulator.

## 2026-08-30: Bound CodeQL to supported product graphs and explicit builds

- **Finding**: GitHub default setup auto-detected the retired Android prototype and attempted an invalid Java/Kotlin autobuild. Its Swift autobuilder guessed the largest Xcode target and remained active far longer than the complete verified iOS gate. Actions, TypeScript/JavaScript and Python analysis passed, but the overall default configuration was misleading and unbounded.
- **Decision/implementation**: Disable CodeQL default setup. Use a path-scoped advanced workflow for Actions, TypeScript/JavaScript and Python on Linux with the extended security query suite, weekly schedules and pull-request/push triggers. A second qualification attempted Swift manual mode with one unsigned generic-iOS `Fotty` target on Xcode 27 and guarded cleanup; it remained inside the instrumented build for more than 17 minutes without reaching analysis, so it was cancelled and not retained as a routine workflow.
- **Boundary**: The inactive Android prototype is intentionally excluded rather than represented as a supported release graph. Re-enable Java/Kotlin scanning only alongside a separate decision to restore and make that project buildable. Swift CodeQL is also not claimed until its Xcode 27 extraction can complete within a reviewed resource budget; Swift retains the complete simulator-free Catalyst unit/generic-iOS Release gate. CodeQL complements those deterministic checks and gitleaks; it does not replace them.

## 2026-08-30: Replace the unsafe Git history and make Search a projection of Home

- **Finding**: GitHub's `main` was an obsolete two-commit snapshot with no active protection or viable CI, while the real 2.0 code existed as hundreds of uncommitted paths on a stale branch. The reachable old history also contained retired Android API credentials. Separately, `SearchView` was orphaned from navigation, fetched a second catalog and could disagree with Home or reject a playable listing for lack of official football detail.
- **Repository decision**: Publish the reviewed working tree as a new root, replace `main` with an exact force-with-lease and remove both stale remote Cursor branches rather than keeping a remote backup that would preserve exposed history. Retain recovery locally. Add Node 24 Web CI, simulator-free Xcode 27 compilation/tests, actionlint, gitleaks, weekly Dependabot and a daily metadata-only provider audit. Enable GitHub secret scanning, push protection, security updates and CodeQL. Test artifacts are bounded and removed.
- **Product decision**: Put Search in Home's masthead and search `HomeSportsDiscovery` directly. Results cover sports, teams, multi-word fixtures, known football leagues, CPL and channels; matching is case/accent insensitive and distinguishes Premier League from Caribbean Premier League. Non-football leagues use a reviewed sport-scoped vocabulary only when league identity is present in the event/source metadata: for example, an NHL feed matches `NHL` and `National Hockey League`, while unrelated international hockey does not. Opaque provider IDs never become free-form search terms. Result rows reuse Home's badges, score/timing truth, opt-in reminders, saving and playback route. Selection is deferred until the search sheet dismisses so presentation layers cannot collide.
- **Evidence/boundaries**: The clean root passes working-tree and one-commit gitleaks scans, 87 web/Worker units, TypeScript, lint with zero errors, Worker dry-run and production web build. The search addition passes the full Catalyst unit suite and unsigned generic iOS Release without a simulator; GitHub repeats repository/iOS gates on the pull request. No build number, device install, TestFlight upload, Worker deployment, provider video request or paid model call.

## 2026-08-30: Treat provider league placement as an identity pipeline, not a label patch

- **Finding**: StreamEx's live Chelsea–Brighton payload used `Brighton and Hove Albion`; the seasonal catalog used `Brighton & Hove Albion`. Independent normalizers and no current-provider release check silently moved the valid Premier League fixture to Other.
- **Decision/implementation**: Generate one canonical senior-club resolver for Swift and TypeScript from the reviewed manifest. Match stream events by canonical teams first, then reconcile a team-and-six-hour-kickoff match to the already-loaded official schedule and let that competition win. Provider marker conflicts emit only redacted local diagnostics. Shared payload vectors and a metadata-only live audit fail the no-simulator release gate before Xcode.
- **Evidence/boundaries**: The first live gate also exposed valid Deportivo wording and a Bundesliga 2 multiview marker; both are classified intentionally, then all three reachable feeds pass. Five shared vectors, 87 web/Worker tests, TypeScript, the complete Catalyst policy suite and generic iOS Release pass. One Xcode 27 direct-test host hang was bounded and cleaned; split build/run passes and is now the gate. No device, simulator, upload, deployment, paid call, video request or Git publication. Full record: `docs/audit/Fotty-Football-Identity-Pipeline-2026-08-30.md`.

## 2026-08-30: Release the single product graph as internal build 46

- **Authority/channel**: The owner requested upload and installation, then explicitly approved the final built-in-encryption declaration, testing notes and assignment to the existing Fotty Internal Smoke group. No new tester/role, direct development install, external submission, simulator, Worker/web deployment, paid call or Git publication.
- **Binary/upload**: The signed normal Release archive reports matching app/extension 2.0.0 (46), expected identifiers, minimum 26.4 and strict signatures. Xcode 27.0 reports `Upload succeeded` at approximately 17:56 AST on 2026-08-29. Source/config/test fingerprint is `01cb09a24fdcfb716f1642e54c904c971daaa0d83455dac397fc349b0daa2a84`; executable SHA-256 is `9ddd57fb9dd5436d3523567418d6d89f915f4fcd741f4d07a68284777a923054`.
- **Apple/status**: Processing completes. After a stale App Store Connect session produced a misleading unsaved localization error, the owner reauthenticated; the approved compliance answer and notes then saved without error. Only Fotty Internal Smoke was assigned. At 09:14 AST on 2026-08-30, a fresh builds-page read shows build 46 Internal / Testing, the expected group and two testers.
- **Installation boundary**: TestFlight 4.3.0 was opened on both connected devices. At 09:18 AST, a direct read confirms Jet iPad installed build 46. Jelani's iPhone remains build 44 even after TestFlight was reopened, so its update is still pending. The iPad version read certifies installation only; availability/installation do not certify launch, retained data or physical acceptance.
- **Resources**: The one bounded build/archive/export root and separate distribution logs are removed; no task-owned build 46 path remains and disk reports about 53 GiB free. Full record: `docs/releases/Fotty-2.0.0-46.md`.

## 2026-08-29: Retire the review-safe product graph after build 45 exposed it to a tester

- **Finding/cause**: Physical TestFlight installation showed `Field Events` and `Reference`. Those were hard-coded review-safe aliases, not provider labels. Build 45's new normal-Release StoreKit check started restricted while `AppTransaction` resolved and could retain or render that state; private Debug build 44 entered the normal app directly, which is why prior device work did not show the defect.
- **Owner decision**: Eliminate the review-safe codebase instead of repairing its transition. Fotty now has one truthful product graph across Debug, Release and TestFlight. A future paid tier requires a separately designed StoreKit product and cannot revive hidden vocabulary or substitute core functionality.
- **Implementation**: Delete `IntegrityService`, `LicenseManager`, ReviewSafe substitutions/plist/directory, StoreKit distribution policy, runtime capability gates and all `APP_REVIEW_SAFE` wrappers/configurations. Restore unconditional Home, real sport/league names, catalog discovery, playback, Matchday/social, reminders, live activities and MultiView. Add unit/UI vocabulary coverage and a release-gate source scan.
- **Version/evidence**: Allocate local 2.0.0 (46). Final-source Catalyst units and generic iOS Release pass without a simulator; focused vocabulary and retired-symbol scans pass. The Home Catalyst UI test compiled but UI automation timed out before execution on two attempts, so no UI pass is claimed. Every bounded temporary Xcode root was removed; about 52 GiB remains free.
- **Distribution boundary at implementation time**: No physical install, TestFlight upload, provider probe, paid model call, server deployment, tester mutation, external submission or Git publication occurred in the correction pass. The 2026-08-30 entry records the later authorized build-46 TestFlight release. Build 46 still needs physical cold-launch labels/Watch/Matchday/FPL acceptance. Full implementation record: `docs/audit/Fotty-Single-Product-Graph-2026-08-29.md`.

## 2026-08-29: Release the consolidated data/platform safety round as internal build 45

- **Authority/channel**: The owner approved TestFlight delivery, then separately approved the exact testing notes and assignment to the existing Fotty Internal Smoke group. No new tester/role, direct install, simulator, external submission, Worker/web deployment, paid call or Git publication.
- **Version/preflight**: Apple independently showed 43 as the latest upload; private 44 was never uploaded. `tools/set-version.sh 2.0.0 45` updated the app, extension and XcodeGen source together. Minimum 26.4 remains because no physical iOS 18 runtime is available.
- **Included scope**: Consolidate build 44's published/local FPL squad boundary, Coach conversation/context invalidation, reviewed 2026/27 competition generation and strict league inference, versioned season/freshness caches and reconciled privacy boundaries. Internal access now uses verified StoreKit `AppTransaction` sandbox/Xcode environments and fails closed for production/unverified/error states. Web dependency modernization remains undeployed source and is not delivered by TestFlight.
- **Evidence/upload**: Reuse recent exact-source 219 Catalyst passes plus one opt-in skip, StoreKit policy coverage, both generic iOS Release configurations, 86/86 web units, zero lint errors (93 warnings), production web build, zero npm vulnerabilities and no-deploy Worker dry-run. The version-only normal archive reports matching 2.0.0 (45), identifiers, minimum 26.4 and strict signatures. Xcode upload succeeds at 15:15:49 AST; source fingerprint is `d44b43cad20f0bb1a0cbe2d1f3e002756c1d905ac667fad43f8cfe157f350131` and executable SHA-256 is `feb43769227cb1c3673e1852a6fa50444ac51146e323d0348c4bd77683b4e652`.
- **Apple/status**: Processing completes; the owner saves the built-in-encryption-only declaration. After explicit approval, English (U.K.) notes are saved and only Fotty Internal Smoke is assigned. At 15:21 AST, Apple independently shows build 45 Internal / Testing with two invitations. Installation/session/crash/feedback dashes are not acceptance evidence. The complete record is `docs/releases/Fotty-2.0.0-45.md`.
- **Resources**: The one `/private/tmp/FottyTF45.*` DerivedData/archive/export root and separate Xcode distribution logs are removed. No Fotty build process or task-owned archive remains; disk reports about 53 GiB free.

## 2026-08-29: Modernize the compatible platform baseline and replace receipt-name trust

- **Authority/scope**: The owner requested the one-time distribution migration plus a current dependency/platform review. This authorizes implementation and qualification, not a version bump, device install, TestFlight upload, Worker deployment, paid model call or simulator.
- **Distribution decision**: `LicenseManager` now verifies `AppTransaction.shared` and grants internal access only for StoreKit-verified `.sandbox` or `.xcode` environments; production, unverified and error states fail closed. Normal Release begins review-safe, resolves asynchronously and retries on activation. Grants are process-local, old unlock defaults are removed, and Release ignores distribution overrides. Debug and the compile-time Review Safe boundary retain their intended roles.
- **Compatible upgrades**: Move the web toolchain to Next 16.3.3, React 19.2.8, Motion 13.1.1, HLS.js 1.7.1, Tailwind/PostCSS 4.3.3, Playwright 1.62.1, pinned Wrangler 4.127.1 and a Node 24 LTS production baseline; emit ES2022, declare npm 11.8.0, ignore Wrangler state and pin the Worker's current compatibility date without enabling Node compatibility it does not use. Remove obsolete Xcode bitcode settings.
- **Measured deferrals**: Do not enable TypeScript 7 while Next rejects the bridge package, ESLint 10 while Next's bundled plugins declare an incompatible peer range, or Swift 6 complete concurrency while the app still has concrete WebKit/AVKit/delegate/shared-state isolation failures. An iOS 18 Release override compiles, but checked-in 26.4 remains until the owner accepts the expanded support/physical-QA matrix.
- **Evidence**: Web units 86/86, lint zero errors/93 warnings, Next production build and zero-vulnerability full/production audits pass. Wrangler dry-run passes without deployment. Final Catalyst execution is 220 with one existing opt-in skip and zero failures; normal and Review Safe generic iOS Release pass without simulators. All owned Xcode/Wrangler temporary output is removed. See `docs/audit/Fotty-Platform-Modernization-Audit-2026-08-29.md`.

## 2026-08-29: Centralize seasonal truth and fail closed at stale-data boundaries

- **Authority**: After the broader outdated-data audit, the owner approved all six proposed remediations. This authorizes local implementation and qualification, not a version bump, device installation, TestFlight upload, Worker deployment, public submission or legal certification.
- **Reference data**: Maintain one reviewed JSON manifest for Premier League, La Liga, Serie A, Bundesliga, Ligue 1, Champions League and Europa League. Generate the Swift and TypeScript catalogs; fail checks for count mismatch, duplicate/colliding aliases, stale generated output or dates after 30 June 2027. Classifiers and fallback browsers consume generated membership and require both current clubs for a domestic league. Non-domestic markers remain Other; explicit UCL identity remains authoritative.
- **FPL and schedule safety**: FPL disk envelopes are version 3, current-season only, endpoint-age-limited, catalog-aware and pruned to 96 files/90 days. Old raw v2 cache is retired. Local planning/profile/review/chat keys derive from the current FPL season. An empty requested football schedule remains empty rather than borrowing older fixtures.
- **Distribution and disclosure**: Remove the client-side Pro key, `FOTTY_FULL_ACCESS` Release condition and remote integrity unlock. Debug and Apple's sandbox/TestFlight receipt retain internal access; public receipts are immutable-safe and cannot inherit an old stored/environment unlock. Update web Terms/Privacy, the iOS Privacy screen and `PrivacyInfo.xcprivacy` to disclose actual local records, public FPL manager IDs, opt-in Cloudflare/DeepSeek Coach processing, third-party playback and local diagnostics; remove inactive email/credential declarations. This is an engineering disclosure reconciliation, not legal advice.
- **Evidence/boundaries**: Shared-generator check, Privacy plist/project lint, 86 web units, lint with zero errors and production web build pass. Seven new Catalyst policies pass in a focused run; the final full suite passes 219 plus one existing opt-in skip. Both generic iOS normal and Review Safe Release compile. An initial Catalyst host stalled while another Xcode device test was active; it was bounded/cleaned and the uncontended reruns passed. No simulator or device was used, and every owned temporary root was removed. Exact scope is in `docs/audit/Fotty-Reference-Data-Freshness-Remediation-2026-08-29.md`.

## 2026-08-29: Use current two-club membership for Premier League catalog inference

- **Finding**: The owner's Coventry premise was outdated—official 2026/27 Premier League material confirms Coventry, Hull and Ipswich were promoted, while Norwich is not a member. The real Fotty defect was an older duplicated club list plus a team-pair helper implemented as either-side matching, allowing Norwich fixtures through when one opponent matched.
- **Decision/implementation**: Keep one season-labelled official 20-club catalog. Home requires both current senior clubs for roster inference, refuses a conflicting provider Premier League label, and excludes cup/youth/friendly/lower-division markers. Champions League identity remains explicit. Club browsing/bootstrap and news inference consume the same catalog; other league pair inference now also means both sides.
- **Status/boundaries**: Local Unreleased source on top of private build 44. Focused policy tests pass 70 plus one optional HLS skip; the full suite passes 212 plus the same skip, with no failures/runtime warnings, and both unsigned iOS Release configurations compile. Exact fingerprint and 812 MB temporary cleanup are in `docs/audit/Fotty-Premier-League-Membership-2026-08-29.md`. Norwich remains under All Football when legitimately listed. No install, upload, deployment, simulator, UI automation, paid call or stream probe.

## 2026-08-28: Continue quality work; guard Coach conversation lifetime

- **Decision**: The owner deferred public-testing discussion and asked to continue improving the existing app. No Ad Hoc/PWA distribution pivot, public review submission or feature removal was selected.
- **Scope**: Pending Coach requests now belong to the shared workspace and are invalidated by clear/disable/disconnect. A planning-context check rejects stale replies without an automatic paid retry; old completions cannot stop a newer request. Recovery uses the normal published-fact/freshness boundary. A failing offline test additionally exposed direct current-total wording missing from both scoring classifiers; both now recognize the bounded phrases while retaining model-backed strategy.
- **Evidence/status**: 209 unit passes plus one optional HLS skip, 82 web/Worker passes, two scoped Catalyst UI passes (existing main-thread warnings retained), and both unsigned iOS Release builds pass. Exact delayed-result tests, the pre-test automation retry, fingerprints and 1.1 GiB temporary cleanup are in `docs/audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md`. Changes are Unreleased, not in installed iPhone 44 or TestFlight 43. The Worker change is not deployed. Paid model quality and physical acceptance remain separate.
- **Boundaries**: No paid Coach calls, Worker deployment, device install, simulator, tester changes, upload or Git publication. Cancellation cannot recall an already-sent request or guarantee cancellation of upstream cost.

## 2026-08-28: Separate published FPL squads from saved drafts; phone-first small fixes

- **Authority**: The owner approved the discussed correction and an iPhone-only installation, with no TestFlight upload. Small fixes are privately tested first; shared fixes/features are batched into deliberate TestFlight releases. Version every acceptance build; small scope does not waive data-integrity checks.
- **Implementation**: `FPLAdvisorViewModel.officialPicks` and `picksGameweek` are immutable-to-edit scoring evidence. Full/foreground and matchday refresh restore the selected saved draft independently. Source notices identify the actual public gameweek and explain deadline publication; switching to published picks preserves the draft. Legacy array storage remains compatible with 43. Validation failures stay in the picker and never report Saved. Coach/public scoring exclude local chips, history, autosubs and multipliers, while model planning is labeled as a draft.
- **Verification/status**: Source is 2.0.0 (44), allocated after read-only Apple verification that 43 is latest. Final suite: 200 unit passes plus one optional HLS skip, no unit runtime warnings; three scoped Catalyst UI passes with existing beta-Mac warnings, 24 Worker contract/scoring passes, signed normal Debug and ReviewSafeRelease iOS build passes. Installed in place on the owner's iPhone, independently version-checked, and passed a 20-second argument-free hold. Linked manager, 15-player saved draft, appearance and saved matches are unchanged. No physical touch/visual acceptance is inferred: the screenshot transport was unavailable. Exact fingerprints, limits and cleanup are in `docs/releases/Fotty-2.0.0-44.md`; TestFlight remains 43.
- **Boundaries**: No simulator, device UI-test runner, iPad change, TestFlight upload, tester/notification mutation, paid-model request, Worker deployment or source publication. The original diagnosis remains a historical record, not current release status. Unsaved Transfer Lab staging still requires Save; private official-app changes need public deadline publication and are not fetched through passwords/cookies.
- **Test identity**: The owner questioned Alexander-Arnold appearing during tests. It was a hard-coded long-name UI fixture, enabled only by the explicit Debug testing flag, not a current official FPL record. A fresh official feed contained no matching player. Fixture/search assertions now use clearly synthetic names (including Test Double-Name); retain that clarity and never substitute stale real players in mock lineups.

## 2026-08-28: Diagnose FPL squad replacement and official-transfer visibility

- **Report**: Pedro Porro replacement appears not to save; the owner clarified it was also made in the official FPL app. Diagnosis only, not implementation or official-team mutation.
- **Findings**: Fotty imports public deadline picks, not authenticated current team state. Previous-event fallback can sit beneath a new-event heading. Separately, valid local squad edits are written to manager-scoped storage but a successful official refresh replaces displayed picks and disables draft mode; saved drafts load only if official picks are absent. Picker dismissal and one-tap recommendation success reporting do not reliably surface rejected changes.
- **Evidence/limits**: Code-path inspection and a time-scoped public API sample establish the mechanisms, not a reproduction of the owner's exact private transfer. The sampled Mac manager is also present in tests and is not confirmed as the phone identity. No app-code changes, builds, simulator, device install, server deployment or paid-model calls. See `docs/audit/Fotty-FPL-Squad-Persistence-Diagnosis-2026-08-28.md` for proposed separate official/draft state and missing regression coverage.

## 2026-08-28: Invite one owner-selected CPL internal tester

- **Authority**: The owner selected one additional trusted participant and, after explanation of the broader Marketing-role permissions, explicitly approved sending the Fotty-only App Store Connect invitation. Store the participant as CPL-03 in repository records, not by email. This does not authorize general beta expansion or changing other users' access.
- **Action/evidence**: Apple explicitly confirms the account invitation was sent. Marketing is the only selected role, Fotty the only selected app, and Create Apps is not granted. The fresh Users list shows Marketing / Resend Invitation but labels scope All Apps; Fotty was the sole chooser app, so restriction against future apps is not verified. Edit App Access remains disabled while the invite is pending. After acceptance, verify/narrow scope before internal-group assignment. The participant is not yet eligible in the group's Add Testers list; do not claim a TestFlight invitation or installation yet. No duplicate invitation or deletion was made.
- **Installed baseline**: At 13:23 AST, the group's two original testers both show Installed 2.0.0 (43). No launch, retained-data, playback or feedback-receipt pass is inferred from installation. `docs/beta/ROUND-01-ACCEPTANCE.md` records the evidence and CPL focus.
- **Boundaries**: No build, simulator, device install, new release, Worker change, external submission, source publication or raw tester-data export.

## 2026-08-28: Begin the approved reliability-first next phase

- **Authority**: The owner accepted the nine-gap recommendations and their order. Start by releasing the five existing fixes and preparing fresh-user evidence. Preserve current UX and TestFlight-first delivery; no new people/roles, paid service, name, external submission or Git publication is selected by this approval.
- **Release**: Apple preflight confirms latest upload 42 and two current testers Installed 42. Allocate 2.0.0 (43). Web/Worker tests pass 81/81, production web build passes, Swift units pass 191 plus one optional soak skip and zero runtime warnings. Two scoped UI audits pass after one permitted pre-test automation timeout retry; each retains a main-thread warning. Current archive/Apple/cleanup outcomes are maintained in `docs/releases/Fotty-2.0.0-43.md`.
- **Service**: Deploy `fafdf5ed-4d37-47e6-82b8-69dd55c3e116`, retaining previous revision `39e913bd-d1fb-48e4-bf56-20be2ba183e4` as rollback reference. Live health, invalid/oversize Coach bodies and missing-scoring zero-token response pass. No real manager or paid model request is used in this smoke; tactical routing remains covered offline.
- **Next-phase evidence**: Add a phased plan, fresh-tester/long-playback ledger and Coach acceptance-case specification. Fix stale build-35 tester-guide references and obsolete Home/Matchday fantasy assertions in the physical QA script. Unperformed tests remain unperformed. Lower-iOS support is a diagnostic assessment, not a deployment-target change; recovery/sync, spend budgets and rebranding retain explicit decision boundaries.
- **Completed release checkpoint**: Apple accepted 43 at 12:37:49 AST and independently completed processing by 12:41 AST. The owner then explicitly approved the same system-encryption declaration, notes and unchanged group at action time. All three were saved; the notes persisted after reload and only Fotty Internal Smoke (two testers) was assigned. At 12:47 AST, the independent builds page shows 43 Internal / Testing with two invites. This verifies availability, not installation, physical acceptance or report receipt. No rebuild/re-upload was needed. Unchanged-source normal Release app/extension also compile with an iOS 18 override, but 43 retains 26.4. The 1.4 GB owned build tree and separate distribution logs are removed, prior web output restored, and 62 GiB free. No paid model tokens were used by the production smoke.

## 2026-08-28: Fix the five audited reliability boundaries locally

- **Authority/scope**: The owner's “ok now we fix those” authorizes the five reproduced playback/FPL/Coach defects and regression tests, not a wholesale rewrite or rollout. Distributed TestFlight remains 2.0.0 (42); these changes are Unreleased. No simulator, direct install, deployment or Git publication.
- **Playback**: A replacement/reset playhead establishes a new baseline; only forward progress clears a stall. Post-start failures/recovery/native candidates are document-owned, DOM media errors are primary-video-owned, and callback ordering prevents a delayed failure from overtaking recovery. Pause/background behavior and provider controls remain intact.
- **FPL/Coach**: Both scoring engines require complete unambiguous picked-player evidence before projection/derived totals. Unknown totals are optional/null, not zero; supported official totals retain incomplete labels. Known gameweek mismatch cannot authorize a current total. Missing/stale scoring yields a low-confidence zero-token rules answer; local freshness uses the oldest picks/live fetch, not a fresh unrelated resource. General tactical advice still uses DeepSeek, while iOS rejects model-origin responses to recognized scoring queries.
- **Request extraction**: `web/workers/playback/src/coach-request.mjs` separates bounded stream reads, parsed/nested shape validation and limiter failures from orchestration. Configured limiter outages fail closed; optional binding behavior and no-client-secret policy are unchanged.
- **Verification**: Original probes 6/6; full web suite 81/81; Mac Catalyst units 191 pass plus one optional live-HLS soak skip, no failures/runtime warnings. Build/cleanup outcomes and remaining physical iPad acceptance are maintained in `docs/audit/Fotty-Complexity-Fixes-2026-08-28.md`. No paid model calls were needed. Preserve the original audit's pre-fix evidence rather than replacing its baseline with passing results.

## 2026-08-28: Read-only complexity audit finds untested playback and FPL boundaries

- **Scope**: The owner approved the proposed audit, not implementation. SwiftLint 0.65.1 measured 161 Swift files; ESLint 9.39.4 measured the active Worker/scoring modules and extracted playback monitor. Retained P2P/conditional code is identified separately from active Watch risk. No app/test/version/production configuration changes, builds, simulators, device operations or deployments.
- **Findings**: Offline execution of unchanged production JavaScript reproduces a false stall after a video-element/playhead reset, unrelated-video errors entering broadcast failure, a missing live-stat row becoming a projected keeper autosub, a scoring question falling through to the model on official-refresh failure, and null JSON escaping controlled request validation. No live API or paid model call was made; the model response was a stub. These are synthetic boundary reproductions, not proof of the cause of a particular physical-device incident.
- **Evidence**: All 11 existing Worker tests pass; the new audit-only probes have one passing control and five violated safety expectations. Swift tests were inspected, not rerun. The application/source fingerprint remains unchanged. Report and reproducible runners/results: `docs/audit/Fotty-Complexity-Audit-2026-08-28.md` and `docs/audit/complexity-2026-08-28/`.
- **Next step, not authorized by this audit**: Fix the false playback stall, missing-data autosub and scoring/model boundary first with regression tests; then auxiliary-media errors, request shape and targeted responsibility extraction. Preserve attempt/cancellation guards and the reminder queue. No blanket rewrite or complexity-score gate was added. Temporary analyzers are removed; disk remains about 63 GiB free.

## 2026-08-28: Consolidate the tested app in internal TestFlight; discuss next steps only

- The owner authorized updating TestFlight, not further feature implementation. Preflight confirms build 35 as the latest Apple upload and the existing two-tester Fotty Internal Smoke group, with feedback on and manual Xcode build assignment. Because build 41 already reached the iPad, allocate 42 without changing app feature code.
- Reuse the exact build-41 source fingerprint and its 184-unit/two-scoped-UI evidence. Fresh optimized normal Release archive passes bundle versions/IDs, OS minimum, strict signatures, compiled icon and empty embedded provider-key checks. Source/config fingerprints stay unchanged; no ReviewSafe substitution.
- Apple accepts the upload at 00:01:49 AST; processing is complete at the 00:03 AST read. The owner approved the built-in-encryption-only answer, tester notes and existing-group assignment. An expired session interrupted the initial declaration save at 06:15 AST; after the owner signed in, a fresh read confirmed it was still missing before the approved retry. **Ready to Test** then verified. Six What to Test tasks/known limits were saved in English (U.K.), only Fotty Internal Smoke was assigned, and its two testers verified unchanged. At 06:18 AST the builds page reports **Internal / Testing** with that group. No rebuild/re-upload was needed. The single 314 MB build/archive/export root and 576 KB distribution logs remain removed; 40 GiB is still free. See `docs/releases/Fotty-2.0.0-42.md`.
- No direct device install, simulator, account/tester/role changes, external beta/App Store submission, server deployment or Git publication. Future product ideas are discussion-only; TestFlight availability is not physical acceptance or feedback receipt.

## 2026-08-27: Approved compact rows and secondary live saving

- The owner's “proceed” approves restoring names/badges left and Watch right, retaining upcoming countdown/reminder controls and moving live saving into a secondary action. Build 41 implements a measured shared row with an accessibility/narrow-width fallback instead of an unconditional action strip. Countdown and error state are not duplicated across layout alternatives.
- Save/Remove remains in each row's native long-press menu and accessibility actions; optional setup/Help explain it. Saving remains silent, and existing saved matches/reminders are preserved. Reminder and stream-retry explanations span the full row. No provider/playback-engine or API changes.
- Verification and iPad outcomes are recorded in `docs/releases/Fotty-2.0.0-41.md`. TestFlight remains 35; only the normal iPad app is within the standing diagnostic authorization. No simulator, physical UI-test helper, iPhone install or Git publication.
- Final evidence: 184 unit passes (one optional skip, no unit warnings), two scoped Catalyst interaction passes (two beta-Mac main-thread warnings), normal/Review Safe Release and signed Debug passes. App/extension versions/signatures and unchanged source hashes verify. iPad independently reports 41, passes the 20-second normal hold, and its portrait capture confirms Watch-right rows, no permanent bookmarks, preserved badges and future countdown/bell controls. Physical menu/bell taps and real reminder delivery/return are not certified.

## 2026-08-27: Owner pauses build-40 layout for density/bookmark discussion

- Build 40 is installed on the iPad, version-checked and passed an argument-free 20-second hold; 181 unit tests and all three iOS build variants pass. The owned 1.1 GB temporary tree was cleaned after interruption. TestFlight remains 35.
- The owner dislikes Watch below names because cards are taller and questions a visible bookmark on already-watchable live rows. The action stack was applied too broadly. Discuss restoring names/badges left and Watch right for live cards; keep future countdown/bell controls and only stack when width/large text requires it. Save-to-Matchday is a secondary quick-return action, not stream readiness. Do not implement this discussion without approval. Physical notification delivery/return and final layout acceptance remain open.

## 2026-08-27: Approved inline countdowns and explicit match reminders

- **Physical follow-up 40**: Build 39 reached the iPad, so the subsequent full-contrast future-row correction advances to 40. The real screenshot caught disabled parent styling dimming future names; plain informational content now stays readable while playback alone is gated. Updated visual tests render actual Home rows. The repeated full unit suite passes 181 tests with one optional skip and no warnings. Final build/device/cleanup evidence is in `docs/releases/Fotty-2.0.0-40.md`. The physical launch helper also accepts CoreDevice's wired `connected` state without dropping its lock, physical-target or installed-app checks.
- **Decision**: The owner approved the opt-in idea. Use scheduled-start countdowns, not guaranteed-availability promises; reveal a play attempt two minutes before start. Remind me schedules a local five-minute alert and saves the match; saving alone stays silent. No new countdown/details screen or automatic playback.
- **Implementation**: Shared timing controls/guards across Home, Matchday and Match Center; MultiView uses the same two-minute window. Per-event failed lookup remains inline with Retry. Stable UTC reminder requests, bounded capacity, persisted consent, exact fresh-ID reconciliation, known status revocation and a serialized revision-checked queue prevent duplicates, overdue alerts and cancelled work resurfacing. Notification taps reveal the saved match in My Matchday. Disk-cache rows cannot erase saved source descriptors during foreground reconciliation.
- **Verification**: Final unit suite: 180 passed, one optional HLS skip, zero runtime warnings. New coverage includes silent save, denial/late permission, cancellation during every async boundary, concurrent opt-ins, reschedules/unknown times, expiry, capacity isolation, route selection, direct-action timing and nonblank themed/narrow controls. iOS/iPad outcomes and the remaining real reminder delivery/tap acceptance are in `docs/releases/Fotty-2.0.0-39.md`.
- **Boundary**: Local notifications cannot learn reschedules while the app is closed; Focus/notification settings may delay or silence them. No new API, model cost, server, provider polling, simulator, device UI-test helper, iPhone install, TestFlight upload or Git publication. Existing iPad-only diagnostic authorization applies.

## 2026-08-27: Approved uniform sport grid and full iPad sport visibility

- **Decision**: The owner approved the discussed tile layout. Every sport gets equal dimensions and a reserved two-line title; the American football label must not make only its own tile taller. Use the iPad's available width and additional rows for all listed sports, without More sports. Compact phones retain the bounded selector and selected-overflow continuity.
- **Implementation**: A small measured SwiftUI layout shares the tallest natural height across every cell and derives columns from actual width plus a Dynamic Type-scaled minimum. The iPad policy remains expanded in compact Split View. No catalog counts, playback ownership, API usage or navigation destinations change. Candidate 38 also includes the previously approved dedicated Appearance/no-Engineering and badge-cache fixes.
- **Verification**: Build 38 is installed and independently version-checked on the physical iPad. Final 155-unit suite passes with one optional soak skipped and no runtime warnings; normal/Review Safe Release and signed Debug pass. Physical Home shows uniform eight-column-plus-overflow-row geometry and real Yankees/Astros badges. A requested Settings capture instead showed Home and is not Settings interaction evidence. Argument-free 20-second launch hold passes. See the build-38 record for boundaries.
- **Next discussion, not implemented**: The owner rejected Open broadcast beginning a lookup only to report no streams. Code uses supported catalog descriptors, not verified availability, and distinguishes Watch/Open broadcast by timing. The owner prefers an inline countdown that becomes tappable about two minutes before start; a separate details screen is unnecessary unless it contains useful match information. Prefer Starts in over Available in because the schedule cannot guarantee provider readiness. Keep a not-ready retry inline. No countdown/routing edit or build 39 was produced while this interaction is being discussed.

## 2026-08-27: Dedicated Appearance, no normal Engineering, discuss equal sport tiles

- **Owner feedback**: The inline Light menu is poorly positioned. Appearance should be a normal Settings destination with clear Light/Dark choices. Engineering is not useful in the everyday interface. American football tiles are taller and iPad should expose more sports, but discuss that layout before changing it.
- **Implemented locally for 38**: Dedicated Appearance row/screen (Dark default, Light, System); Engineering removed from normal Settings even in Debug, with Report a problem retained. The real iPad revealed missing baseball crests: preserve bundled badge seeds when loading sparse persisted cache and extend existing static ESPN NBA/MLB artwork using verified current catalog names/URLs. No new runtime catalog API. Build 37 remains on the iPad, 35 on TestFlight.
- **Pending decision**: Equal tile-height/label slots and width-aware iPad capacity are proposals only. No new tile geometry/capacity edit or build-38 install was made after the owner requested discussion. Real touch, appearance-screen persistence and final baseball image acceptance remain open. See `docs/audit/Fotty-Appearance-and-Identity-2026-08-27.md`.

## 2026-08-27: Restore sports identity and add optional light appearance

- **Decision**: The owner likes the compact all-sports Home but considers real team badges and recognisable sport imagery essential to Fotty's identity. Restore badges beside each team and equipment symbols in sport tiles/menus; do not undo the approved layout or rename the app. The owner explicitly authorized app-wide light mode after the playback fix, with Dark as default.
- **Implementation**: Reuse cached provider/catalog badges and matched football crests; fit artwork rather than cropping it, observe catalog updates, and keep named initials only when artwork is missing. Channels/unpaired events have no invented teams. One shared sport-symbol mapping serves normal and Review Safe catalog adapters. `FottyAppearance` persists Dark/Light/System; adaptive surfaces, text, borders, status colours and shadows support the choice. Amber text and gold fill are separate roles. FPL sheets inherit appearance; pitch artwork and playback remain dark. No root identity reset, new image provider, paid API or FPL data migration.
- **Evidence/boundary**: Build 37 follows the physically installed build 36. Final-source unit suite: 148 passed, one optional HLS soak skipped, no failures/runtime warnings. Both-mode contrast and real symbol availability pass; light/dark iPad-width and narrow large-Type component renderings were inspected. Initial test compilation needed a locally scoped fixture helper; one old test expected the replaced athlete icon and was updated to the new equipment contract. Physical and build outcomes are in `docs/audit/Fotty-Appearance-and-Identity-2026-08-27.md`. TestFlight remains 35 until separately uploaded. No simulator, device test helper, external distribution or Git publication.

## 2026-08-27: Preserve provider transport taps and deliberate pause state

- **Decision**: The CPL centre/lower-left pause/resume report is a control-ownership and state-consistency defect, not a reason to add another central button. Provider controls remain canonical; Fotty's fallback stays bounded at the upper-right and fades while playing.
- **Implementation**: Remove the UIKit surface tap recognizer and observe DOM clicks passively in each frame. Report actual decoded-video pause/play, tied to document/source/attempt; rejected Play restores paused UI. Intentional pause cancels handoff and ignores delayed stall/recovery callbacks, while genuine interruption recovery is preserved. `_blank` prevention no longer swallows legitimate JavaScript handlers; known nuisance blocking stays. Executing injected JavaScript also caught and fixed an uninterpolated startup timer.
- **Verification**: Playback-source suite passed 144 tests with one optional HLS skip. Signed normal 2.0.0 (36) was installed on the requested iPad Air 4, independently version-checked, launched and survived 30 seconds. The exact live centre/lower-left pause-and-resume touch acceptance remains open. Computer Use decoded Willow video on Mac, but its media action timed out, so no successful tap claim follows. See `docs/audit/Fotty-Playback-Controls-2026-08-27.md`. Direct iPad testing is the owner's explicit exception to TestFlight-first delivery.

## 2026-08-27: Implement the approved compact all-sports Home

- **Decision**: The owner approved the interactive cross-sport Home concept. Make activity discoverable without visiting every category. Keep the name and four-tab structure; the additional light-mode question remains a recommendation, not an app-wide conversion or upload instruction.
- **Implementation**: All sports default; five visible sport activity tiles plus an activity-aware overflow; a maximum three-event mixed-sport Now & next list; two later events; and See all on Home's navigation stack. Native competition/cricket filtering, saved/followed Matchday and existing source-gated playback routes remain. Exact IDs or sport/start/team-pair duplicates are collapsed for presentation without a canonical-ID migration. Source-free CPL rows retain dated provenance; channels and uncertain timings do not become live events. Current official state has priority, but an unavailable/stopped score poller cannot perpetuate stale in-play state beyond the bounded freshness rule. Non-team catalog titles no longer invent an Away opponent.
- **Quality**: An interaction test caught an accessibility-container/button mismatch, corrected in the view. Computer Use inspection caught real-catalog non-team title and sport-label defects. Repeated beta-Mac contrast flags were checked against captured pixels and a separate >=7:1 actual-color unit test. A trial scoped exception merely exposed additional false-positive candidates, including white headings on black and black Watch text on amber; those new exceptions were removed. The original contrast audit remains unmodified and is not claimed clean. See the audit record for final unit/UI/build evidence and limitations; physical contrast acceptance remains open.
- **Boundary**: Local, unreleased work on build 35; no additional API/model use, source probing, playback-engine changes, simulator, device install, upload, server deployment, tester changes or Git publication. Light mode requires a coherent semantic-palette and whole-app accessibility pass. Preserve one bounded DerivedData directory, two jobs and cleanup.

## 2026-08-27: Keep fantasy in FPL and distinguish cricket channels from CPL fixtures

- **Decision**: The owner's “proceed” approves removing redundant Home/Matchday FPL promotion and the Match Center fantasy panel, plus improving discovery of existing Willow/cricket coverage. Preserve the dedicated FPL workspace, manager/data/drafts, followed teams and saved broadcasts.
- **Implementation**: Cricket gains All cricket / CPL / Channels filters and separate Willow/Fox rows with source-gated Open channel actions. Saved channels never expire from negative date sentinels. The 39-fixture CPL 2026 snapshot is explicitly dated and season-bounded, includes the July TKR correction and Barbados Tridents name, and preserves Jamaica's UTC−5 starts. Stream enrichment requires both franchises and kickoff within an hour; neither channel names nor stale saved schedule sources can invent match coverage. Shared timing uses football/T20-specific estimates and avoids a false two-hour final for unknown cricket formats.
- **Evidence**: The provider returned six Willow variants (HD/SD pairs for Willow, Willow 2 and Willow Sports). Actual decoded Willow video showed the current Jamaica Kingsmen–St Kitts & Nevis Patriots CPL match on Catalyst. The visual pass caught channel counts labelled as matches and a synthetic “vs Away” player title; both were corrected. Exact final checks, initial failures and evidence limits are recorded in `docs/audit/Fotty-Cricket-and-Tab-Separation-2026-08-27.md`.
- **Boundary**: Local implementation only; build 35 remains distributed. No new paid API, official Willow account integration, server deployment, simulator, device install, tester change or Git publication. Future CPL releases require manually checking schedule announcements; this snapshot is not a live feed or programme guide. Retain TestFlight-first delivery and the separate clean-ancestry publication requirement.

## 2026-08-27: Upload build 35 through the internal-only TestFlight channel

- **Preflight**: The owner restored browser sign-in. App Store Connect listed `2.0.0 (34)` as the only completed upload and Fotty Internal Smoke as the existing group (two testers, feedback on, manual Xcode build assignment). `tools/set-version.sh` allocated 35 across app, extension and `project.yml` without changing marketing version or app behaviour.
- **Build**: Reused the immediately preceding final-source unit/UI/compile evidence; created one optimized normal Release archive, generic iOS, automatic signing, two jobs. Both bundle identifiers, versions, iOS 26.4 minimum and strict signatures passed. Provider API-key values were explicitly empty. The source/config fingerprint stayed unchanged across archive; see `docs/releases/Fotty-2.0.0-35.md`.
- **Upload**: Xcode 27.0 reported `EXPORT SUCCEEDED` and `Upload succeeded` at 19:12 AST. App Store Connect completed processing. The owner saved the encryption declaration after the source/binary-based explanation; the accepted **Ready to Test** state was independently verified. The browser workflow then saved the five-task What to Test notes and assigned only Fotty Internal Smoke. At 19:21 AST the fresh builds page showed **Internal / Testing** with the expected group; its two testers and account roles remain unchanged. No rebuild or re-upload was needed. Availability is confirmed, not tester installation or feedback receipt.
- **Boundaries/resources**: No direct device install, simulator, device UI-test runner, server deployment, tester/role change, external review or Git publication. The 305 MB owned archive/build/export directory and 640 KB Xcode distribution logs were removed; 41 GiB remains free. Fresh physical TestFlight acceptance and a confirmed received feedback report remain wider-beta gates.

## 2026-08-27: Make internal TestFlight the normal update channel

- **Decision**: The owner requested uploading the UI refinements and using TestFlight instead of cable installs from now on. Use the normal `Fotty` Release app for the existing internal group; retain direct-device tools only for explicitly requested diagnostics. Do not expand testers, submit externally, or publish Git history as part of this request.
- **Preparation**: Added `ExportOptions-TestFlightInternal.plist` with automatic signing, symbol upload, internal-only distribution and automatic build-number management disabled. Replaced the stale ReviewSafe/simulator TestFlight checklist, and changed the release lifecycle to TestFlight-installed device acceptance before wider beta invitations. Apple's installed Xcode export help and official TestFlight documentation support the chosen options.
- **Current blocker**: App Store Connect opens at sign-in; no alternative connected browser is available. The owner must sign in before the latest uploaded build and existing group can be checked. No next number has been chosen, archive made or upload attempted; all UI changes remain local. Export/project plists and release-owned whitespace checks pass. No simulator, device install, signing-account change or Git operation occurred; disk remains 41 GiB free.

## 2026-08-27: Implement the approved UI refinement without changing football/FPL authorities

- **Decision**: The owner's subsequent “proceed” approves implementation of the audit priorities. Retain the amber identity, pitch and separate Home/Matchday purposes. Improve readable text, accurate labels, continuity and existing workflows rather than adding unrelated features.
- **Implementation**: FPL now has a root-owned workspace session, per-tool scroll restoration, cached refresh on return/foreground, manager-selection-safe restoration, and retained Coach draft/pending state and comparison IDs. Meaningful FPL text uses semantic sizing; long pitch names wrap and large text switches to a roster. Difficulty uses one numbered, contrast-tested palette. Plan emphasizes the next decision, uses measured-width evidence columns and groups existing Tools by purpose. Comparison has bounded player/club search; captain rank and point estimates are explicitly distinct. Home preserves unknown club identity and labels future broadcasts accurately. Matchday removes duplicated relevance and date-groups later fixtures. Settings demotes local identity, separates alert types, and gives report fields persistent required labels. Controls gain 44-point targets and shared Live Pulse respects Reduce Motion.
- **Preserved contracts**: No FPL points/transfer/ranking mathematics, official submission, provider resolution, PiP eligibility, source switching, auto-hide timing or unmute behavior was changed. The only advisor-engine change is explanatory captain copy. Explicit pull-to-refresh retains its cache-clearing semantics; ordinary FPL return uses existing TTL caches.
- **Verification**: The final unit run passes 122 tests with zero failures/runtime warnings and one opt-in HLS skip. Fourteen distinct scoped Catalyst checks pass, including all six Home accessibility scopes after fixing downloaded-badge descriptions, five other surface audits and three interaction checks. The Debug fixture now exercises a full squad, long names, five defenders, fixtures and captain cards instead of an empty Squad. Final normal iOS and Review Safe builds pass unsigned. Visual review confirmed wide Plan columns and wrapping; native Home filter styling is deliberately retained after tint/Menu experiments caused accessibility regressions. Some UI runs emitted main-thread warnings on the beta Mac. Full results and limits are in `docs/audit/Fotty-UI-Refinement-2026-08-27.md`; these checks do not certify physical devices or engagement.
- **Release/resource boundary**: This remains local and unreleased on the build-33 source baseline; no upload, physical installation or Git publication. Preserve the cleaned-history replay requirement. All configurations share one temporary DerivedData root with two jobs and cleanup; no simulator. Physical Display Zoom/keyboard/daylight/VoiceOver and upstream duplicate identity remain explicit follow-up checks.

## 2026-08-27: UI audit recommends refinement, not another feature expansion

- **Scope**: Read-only UI/UX review of current build-33 source plus the unreleased beta-usability patch. The owner requested judgment, not implementation. Recommendations are not approved design changes or new release gates.
- **Findings**: A credible closed-beta foundation, but not yet premium. Priorities are fixed 7–10-point meaningful FPL text, low-contrast fixture chips, ambiguous future-broadcast/current-gameweek labels, FPL workspace reset across main-tab changes, over-abbreviated club names, technical copy, and inconsistent tool/control hierarchy. Keep the amber identity, football pitch, distinct Home/Matchday jobs and in-app playback recovery.
- **Evidence**: Current-source Catalyst inspection covered Home, Matchday, four FPL workspaces, Transfer Lab, Captain, the pre-deadline Live Points state, Settings, Help and report preparation at narrow/expanded window sizes. Source review covered remaining tools, compact paths, onboarding, Match Center, player and system surfaces. Two Price Radar accessibility inspections stalled in hierarchy enumeration on the beta Mac; ordinary device freezing is not established. No new physical-device, provider-playback, VoiceOver or retention claim is made.
- **Artifact**: `docs/audit/Fotty-UI-UX-Audit-2026-08-27.md` separates observed/source-only evidence, priorities, screen recommendations and later tester tasks. One temporary Catalyst build succeeded; its 329 MB output and captures were removed, leaving about 42 GiB free. No app/source/version changes, deployment or Git publication occurred.

## 2026-08-27: Close newcomer dead ends before widening the internal beta

- **Decision**: Make Help and report preparation native/offline, require explicit confirmation of a looked-up FPL team, keep setup optional, and describe current capabilities honestly. Preparing or copying a report is not submission; foreground match updates are not background push; Fotty draft changes are not official FPL transactions.
- **Why**: New testers could otherwise follow a retired help URL, become stuck on an incorrect manager ID, expect unsupported alerts, or miss the distinction between Home discovery and personal Matchday.
- **Implementation**: Added official-link parsing and cancellable identity lookup; manager switching invalidates pending manager/review/league/rival/Coach work without deleting scoped drafts. Added shared native Help/report sheets with persisted drafts, build/device context and opt-in previewable diagnostics. Home tips and empty Matchday use direct root navigation callbacks, not persisted preferences as a navigation bus. Team selection has adaptive text, search cancellation and explicit recovery states. Added `docs/BETA-TESTER-GUIDE.md` and focused policy/navigation checks.
- **Interaction corrections**: Inactive tabs need an explicit rectangular content shape so the gap around their icon/label remains clickable; tabs also expose selection. Catalyst checks use native mouse clicks and assert the destination/selection. Setup-dismissal UI tests use an isolated, mutable Debug preference suite instead of an immutable launch-argument override. The report uses directly labeled headings/controls, avoiding the unlabeled native form-header and disclosure-image audit failures without suppressing app-owned accessibility issues.
- **UI verification**: All three new journeys passed on Mac Catalyst: native Help/report preparation with text-clipping/description audit, official FPL link entry without implicit connection, and Home → FPL → Home → setup dismissal. The strengthened rapid-tab/foreground test, Dashboard contrast/traits and Settings Dynamic Type checks also passed after the interaction corrections; the eleven existing release-scope accessibility audits had passed earlier in this work. One Xcode pre-test automation-mode timeout required the runner's bounded retry. Runtime main-thread/QoS warnings were still emitted on the beta Mac; this is not a zero-warning claim or fresh iPhone/iPad certification.
- **Policy verification**: Final-source Catalyst results contain 117 passing tests, zero failures and zero runtime warnings, with only the explicitly opt-in reference-HLS soak skipped. The twelve beta-usability tests cover strict parsing, retry/cancellation/stale-response isolation, confirmation separation, feedback context/opt-in, setup policy and manager-state reset boundaries.
- **Build verification**: The final-source normal signed generic-iOS Release and unsigned ReviewSafeRelease builds both succeeded. Project-plist validation, shell syntax and `git diff --check` passed. Builds ran sequentially in one reused, trap-cleaned temporary directory; no simulator, device deployment, archive, TestFlight upload or Git publication was performed.
- **Distribution boundary**: This is a local, unreleased patch. Do not infer that existing TestFlight testers have it or that build-33 hardware acceptance covers the new flows. A higher build number, fresh supported-device checks and one confirmed received TestFlight report remain the next beta-expansion gate. The old local Git ancestry remains frozen; no source publication is authorized by local implementation.

## 2026-08-26: GitHub purge closes the final Fotty 2.0 release gate
- **Decision**: Accept GitHub Support's closed-ticket response only after independent API, web, PR-ref, and fresh-clone verification. Close the repository-security gate while keeping the dirty old local branch frozen; any later source publication must repeat the proven Git-aware replay onto clean ancestry.
- **Why**: The support response is necessary server-side evidence, but the accepted contract requires independently proving that neither obsolete commit remains publicly retrievable and that the rewritten advertised history did not move unexpectedly.
- **Verification**: GitHub closed ticket `#4701297` and reported that unreferenced commits were cleared. Authenticated commit API calls now return `No commit found` for `74c8b1627d24a8b8368b903fee83f8dda94d0a61` and `82f9cc431b5d5e078dd8f4cba4285ed4dfc8e237`; both public commit pages return HTTP 404; `refs/pull/1/{head,merge}` and `refs/pull/2/{head,merge}` are absent. A new bare fetch of public heads/tags contains neither old commit nor `cert.json`. The cleaned branch heads remain `5912bee72390315de2799d51073f9e72c27b4602` and `8f67a85fe4de2ce3c8e0214f7d3738b7b7f208d8`; `main` remains `c0a7d5b0fcb0b03125721101ba979cedf51062fb`; the empty tag fingerprint is unchanged. Temporary verification directories were deleted.

## 2026-08-26: GitHub acknowledges active pull-request-reference cleanup
- **Decision**: Treat GitHub Support's acknowledgment as progress, not completion. Keep the repository-security gate open until Support reports completion and both obsolete commits fail independent API/web reachability checks.
- **Why**: The Support agent confirmed that the pull-request reference is being cleared, but both obsolete commit IDs remain retrievable at this checkpoint. Closing the gate on an email acknowledgment would weaken the accepted evidence standard.
- **Verification**: Ticket `#4701297` remains open and contains a GitHub Support reply stating that the pull-request reference is currently being cleared and a completion update will follow. Immediately afterward, both obsolete commit API queries still succeeded. The six-hour read-only monitor remains active.

## 2026-08-26: The completion authority maps all seven agreed pillars explicitly
- **Decision**: Keep the five connected user journeys as the product outcome model and define seven implementation pillars beneath them: data truth/identity, playback reliability, FPL decision system, Smart Coach, Matchday UX, native system experience, and quality/release discipline. Require the completion report to name current implementation authority and verification evidence for every pillar.
- **Why**: The source and evidence already covered the full program, but the durable Project Memory still listed four pre-2.0 strategy bullets and the report distributed evidence across journey and gate sections. A strict completion audit should not require readers to infer whether all seven agreed areas were actually delivered.
- **Verification**: The accepted contract and Project Memory now name the same seven pillars. The completion report maps each to source ownership and automated, production, Catalyst, or physical evidence. All product/device pillars are implemented and verified; only GitHub Support ticket `#4701297` and independent obsolete-commit unreachability remain open under the quality/security pillar.

## 2026-08-26: Prove the release tree can move to clean ancestry before publishing it
- **Decision**: Do not merge, rebase, reset, or push the dirty old local feature branch. Prove the migration using a disposable detached worktree based on the cleaned remote branch, a binary tracked-tree delta, and only Git-visible untracked files. Remove that worktree after validation and repeat the same boundary only when the Support purge is complete and the clean-ancestry release commit is ready to be created.
- **Why**: The current 373-path working copy contains the complete Fotty 2.0 program but its local HEAD predates the sensitive-history rewrite. Pushing or merging it could reintroduce the dead credential's ancestry, while copying the whole directory could include ignored build output or secrets. A Git-aware replay preserves the intended source tree without either risk.
- **Verification**: The clean branch differs from the old local HEAD only by deletion of `cert.json`. The temporary replay reproduced 310 tracked changes and 120 Git-visible untracked files; sorted path manifests matched, every changed/untracked file matched byte-for-byte, `cert.json` was absent, and `git diff --check` passed. Cleanup left zero replay directories and preserved the active branch, local HEAD `3855bd53c9dfc543832333924ee21db2175f11bc`, and 373-path dirty status.

## 2026-08-26: GitHub Support ticket 4701297 requests the retained-object purge
- **Decision**: Submit the prepared sensitive-data cleanup request through the authenticated GitHub Support repository route. Categorize it as a repository branch/history problem, not repository deletion, and include no credential value or attachment.
- **Why**: Repository owners can rewrite advertised branches but GitHub's `refs/pull/*` are read-only. The obsolete commits remain publicly retrievable through PR heads and cached objects even though the credential is revoked and fresh public branch/tag history is clean.
- **Verification**: GitHub displayed “Your message has been successfully submitted,” and the authenticated ticket list shows open ticket `#4701297`, “Purge sensitive-data commits retained by closed PR refs,” created 2026-08-26 for `jetboss`. The request includes repository name, two affected PRs, both first-changed commits, clean replacement heads, unchanged `main`/tags, and no-LFS confirmation. The 2.0 gate remains open until GitHub completes the purge and both obsolete commits are independently unreachable.

## 2026-08-26: Advertised branches are clean; GitHub retained-object purge remains
- **Decision**: With explicit owner authorization, close pull requests 1 and 2, rewrite `cert.json` from a disposable mirror, and atomically force-update only the two affected advertised branches. Preserve `main`, tags, and the 373-path dirty release checkout. Do not close the Fotty 2.0 security gate until GitHub purges the obsolete closed-PR/cache objects and both old commits are independently unreachable.
- **Why**: Fresh mirror inspection expanded the original one-branch assumption to two independent first-changed commits and six changed refs: two branch heads plus head/merge refs for PRs 1 and 2. Branch owners can clean the advertised heads but cannot force-update GitHub's retained pull-request refs. Rewriting the active dirty checkout would risk release work, while a mirror-wide push would move refs outside the inspected scope.
- **Verification**: `git-filter-repo` 2.47.0 deterministically produced branch heads `5912bee72390315de2799d51073f9e72c27b4602` and `8f67a85fe4de2ce3c8e0214f7d3738b7b7f208d8`; GitHub accepted both in one atomic forced update. A new bare fetch of public heads/tags cannot reach `cert.json`; `main` remains `c0a7d5b0fcb0b03125721101ba979cedf51062fb` and the empty tag fingerprint is unchanged. GitHub still returns obsolete commits `74c8b1627d24a8b8368b903fee83f8dda94d0a61` and `82f9cc431b5d5e078dd8f4cba4285ed4dfc8e237`, and the closed PR records still identify their old heads. The local branch, local HEAD, and dirty-path count were identical before and after refreshing only the two remote-tracking refs; all disposable directories were removed.

## 2026-08-26: Owner confirmation closes the two physical interaction gates
- **Decision**: Accept the product owner's direct hardware confirmation that large-text interaction works on both the supported iPhone and iPad and that the real alert/Live-Activity interaction returned to the correct match/player. Keep the automated Catalyst evidence and typed routing tests as supporting coverage, not substitutes for this confirmation.
- **Why**: CoreDevice can launch and observe the normal process but cannot change Dynamic Type or tap system-owned notification and Live Activity surfaces. Those two gates deliberately required a person's direct interaction, and the owner has now supplied it.
- **Verification**: In response to the explicit two-item confirmation—large text on both devices, and notification/Live-Activity tap opening the correct destination—the owner answered “yes for both.” The product contract, QA playbook, Roadmap, Risks, Project Memory, and completion report now mark physical interaction acceptance complete. The only remaining Fotty 2.0 gate is removal of the already-revoked tunnel credential from the affected public Git history.

## 2026-08-26: Delete every retired Cloudflare Tunnel and close credential revocation
- **Decision**: With explicit owner authorization, delete every Cloudflare Tunnel because the homelab no longer exists. Do not touch Cloudflare Workers, zones, domains, or DNS records. Treat credential revocation as complete only after the historical `cert.json` Tunnel ID matches the deleted object and every accessible account reports zero active tunnels; keep public Git-history removal as a separate gate.
- **Why**: The exposed JSON credential was tunnel-specific and non-expiring. Deleting the file from the working tree could not invalidate historical copies, while creating a replacement tunnel would serve no purpose for a retired homelab. The active Fotty playback and Coach edge service is a Worker and does not depend on the tunnel.
- **Verification**: The authenticated Cloudflare API enumerated four accounts and found one non-deleted tunnel, the already-down `manga-api`. Deletion succeeded at 2026-08-26T13:33:04Z; all four accounts then reported zero active tunnels. A field-limited comparison confirmed that commit `82f9cc4`'s `cert.json` names the deleted Tunnel ID without printing its secret. `https://fotty-playback-v3.adaptive-rhubarb.workers.dev/health` remained HTTP 200. The dead credential is still reachable on the local/remote feature branch and stash, so fresh-clone GitHub history cleanup remains open.

## 2026-08-26: Exact build 33 survives the normal-app physical launch gate
- **Decision**: Accept one bounded 60-second normal-app foreground hold on each authorized physical device as exact-candidate process-survival evidence. Do not interpret a CoreDevice process poll as proof of large-Dynamic-Type interaction, alert/Live-Activity return, or active-stream playback.
- **Why**: Build 33 had been strictly verified and installed while the devices were locked, so its launch state remained behind older interaction evidence. Once both devices were naturally unlocked, the existing physical-only runner could close that narrow gap without a rebuild, simulator, synthetic touch, screenshot, or UI-test runner.
- **Verification**: `com.jelani.Fotty` `2.0.0 (33)` launched and remained present through 60-second holds on the authorized iPhone 15 Pro Max and iPad Air. A post-run app inventory showed only the normal Fotty app on each device; no Xcode/UI-test process or Fotty temporary path remained, and the workstation retained 53 GiB free. The completion authority exposes exactly three open gates: direct physical large Dynamic Type, real alert/Live-Activity return, and removal of the now-revoked tunnel credential from affected public Git history.

## 2026-08-26: The completion authority exposes exactly three open gates
- **Decision**: Keep the accepted 2.0 product scope intact while making its Definition of Done match the evidence: active playback controls/lifecycle acceptance is complete; direct physical large Dynamic Type, a real alert/Live Activity return, and tunnel-credential history cleanup remain open. The contract now identifies `1.8.4 (11)` as its starting baseline and `2.0.0 (33)` as the current candidate.
- **Why**: One bundled manual checkbox obscured that every playback item except the system-return interaction had already passed, while the later-discovered repository credential exposure was absent from the accepted completion authority. A completion audit must neither hide completed evidence nor omit a blocking release requirement.
- **Verification**: The product contract, QA playbook, Roadmap, Risks, Project Memory, and completion report all identify the same build-33 candidate and the same three remaining physical/security gates. The completion report retains granular passed evidence for playback, FPL, widget, accessibility, builds, analysis, and exact-device installation.

## 2026-08-26: The generated brain bundle uses the canonical build-33 QA playbook
- **Decision**: `tools/notebooklm-refresh.sh` now embeds `docs/notebooklm/QA-Playbook.md`; the obsolete `Fotty-QA-Playbook.md` is no longer a generated-bundle source. NotebookLM guidance points first to the generated master source and names only canonical focused files.
- **Why**: The refresh completed successfully but silently embedded a May 7 P2P-era checklist instead of the current no-simulator build-33 release checklist. That made a green memory refresh an unreliable proof that agents would receive current QA constraints.
- **Verification**: Shell syntax and `git diff --check` pass. Regenerating the bundle includes the 2026-08-26 playbook, the exact build-33 aggregate result, and the remaining direct physical procedure; the obsolete May QA header and P2P source-switching script are absent from the generated QA section.

## 2026-08-26: Build 33 closes the aggregate Catalyst gate
- **Decision**: Accept the exact build-33 Mac Catalyst release gate as complete after one invocation passed all eleven accessibility audits plus rapid navigation/foreground recovery. Keep physical large-Type, notification/Live Activity return, and credential-remediation gates separate; Catalyst evidence does not waive them.
- **Why**: The first aggregate attempt correctly stopped at the lock guard. Once the Mac was naturally unlocked, the full candidate needed one uninterrupted run to prove the individually green audits also coexist under the release runner without cross-test state leakage.
- **Verification**: `tools/catalyst-ui-release-gate.sh` ran sequentially with two Xcode jobs and no simulator. Hit regions, text clipping, descriptions, Dashboard/FPL/Matchday/Settings/Match Center/Player Dynamic Type, contrast/traits, element detection, and rapid tab/foreground recovery all passed with no retry. The cleanup trap removed the owned `/private/tmp/FottyCatalystUIReleaseGate.*` DerivedData root; zero Fotty temporary targets and zero Xcode/test processes remained afterward.

## 2026-08-25: Contain the tunnel-credential cleanup to the affected branch
- **Decision**: Treat `cert.json` as a tunnel-specific, locally managed Cloudflare credential that must be replaced/revoked before release. `origin/main` and tags are clean; commit `82f9cc4` and `origin/cursor/docs-world-cup-readiness-audit` are the identified advertised-history exposure. Perform GitHub's sensitive-data rewrite from a fresh disposable clone only after owner approval and Cloudflare revocation; never run `git-filter-repo` in the 371-change release working copy.
- **Why**: Deleting and ignoring the file protects future commits but does not invalidate a non-expiring tunnel credential or remove cached Git history. A repository-wide rewrite without first proving the ref footprint would create unnecessary risk, while rewriting the dirty active checkout could lose or contaminate the release work.
- **Verification**: `git for-each-ref --contains=82f9cc4` resolves only the local/remote feature branch; `origin/main` is an ancestor of the current branch and does not contain the exposure commit; scanning every `origin/*` tree finds `cert.json` only on that branch. The redaction, Cloudflare replacement/revocation, fresh-clone `git-filter-repo`, changed-ref review, GitHub Support cleanup, and collaborator-reclone sequence is recorded in `docs/RELEASE-PROCESS.md` without exposing a credential value.

## 2026-08-25: Build 33 covers every named surface at large Type
- **Decision**: Advance to `2.0.0 (33)` and add explicit Debug-only, network-free presentation routes for catalog Match Center and the truthful no-source Player recovery state. Direct-launch Matchday and Settings audits join the existing Home and four-workspace FPL coverage. Preserve a loaded catalog-only Match Center on resume instead of starting an unnecessary repository refresh.
- **Why**: The physical devices and later the Mac were passcode-locked while the owner slept. The release contract still called for large-Type review of every named surface. Deterministic Debug presentation routes provide repeatable layout evidence without a simulator, provider request, manager account, synthetic device touch, or physical UI-test runner, while Release builds exclude the routes.
- **Verification**: Matchday, Settings, Match Center, and Player Dynamic Type audits pass against the build-33 source before the build-number-only advance; Home and FPL had already passed, so all eleven constituent accessibility audits now have green evidence. The complete exact build-33 Swift suite, normal and Review Safe Release, and generic-iOS analyzer pass. One strictly seal-verified signed artifact installed on both authorized locked devices and each independently reports `2.0.0 (33)`; no UI-test runner is installed. The guarded one-shot eleven-audit-plus-rapid-navigation runner correctly refused to bypass the locked Mac and remains the only automated rerun pending unlock.

## 2026-08-25: Build 32 makes FPL large-Type coverage deterministic
- **Decision**: Advance to `2.0.0 (32)` and add an explicit `FOTTY_FPL_UI_TESTING=1` fixture that exists only in Debug. Launch Plan, Squad, Coach, and Tools directly through the allowlisted Debug workspace route for Catalyst accessibility audits instead of relying on Xcode 27 beta's unreliable synthesized workspace taps. The fixture supplies shell state and a structured Coach response without a manager account, network request, or persisted chat.
- **Why**: The final autonomous review needed evidence across every FPL workspace while both physical devices were passcode-locked. A clean Catalyst test container correctly stopped at Manager ID onboarding, and synthesized SwiftUI workspace taps did not change the visible workspace on this beta toolchain. Neither condition was a product defect, but allowing them to skip FPL layout coverage would leave the large-Type claim unproven.
- **Verification**: Exact build 32 passes the complete Swift suite, normal and Review Safe generic-iOS Release builds, generic-iOS static analysis, seven Catalyst accessibility audits, and rapid-navigation/foreground recovery. The FPL audit covers Plan, Squad, Coach, and Tools and requires both the Coach quick-prompt control and a structured response. A separate source contract proves quick prompts clear focus through the shared send path before adding a message. One strictly seal-verified signed artifact installed successfully while both devices were locked, and each independently reports `2.0.0 (32)`; no UI-test runner is installed. The install was intentionally not followed by an overnight device launch.

## 2026-08-25: Build 31 makes the small deadline widget's source visible
- **Decision**: Advance to `2.0.0 (31)` and show the deadline entry's source label directly in the small widget, matching the medium presentation. Retain the typed `fotty://fpl` route and small/medium family boundary.
- **Why**: The final native-system audit found that `Official FPL` was visible in the medium widget and available in the small widget's accessibility summary, but not visually present in the small widget. The accepted contract requires both sizes to show deadline and source; accessibility-only text did not satisfy that promise.
- **Verification**: A regression source contract proves both supported families, the small-family source label, and the typed FPL route. The complete Swift suite, normal and Review Safe Release, generic-iOS static analysis, and all six Catalyst accessibility audits plus rapid-navigation/foreground recovery pass. One strictly verified signed artifact is installed on both authorized devices, and each independently reports `2.0.0 (31)`. The owner confirmed the physical small/medium widget presentation and FPL tap route work.

## 2026-08-25: Builds 29–30 close the final Dashboard audit and reject a provider VPN solicitation
- **Decision**: Advance to `2.0.0 (29)` after the exact Catalyst contrast audit found the Home empty-feed recovery text too muted and its Refresh action insufficiently contrasted, then to `2.0.0 (30)` after build-29 hardware playback exposed a provider-origin `VPN Recommended / Tap to Install and Continue Watching` solicitation. The empty state is now an explicit high-contrast recovery card. WebKit suppresses only the matched VPN/install/continue-watching alert or text ancestor, and refuses to remove any candidate that owns video, owns an iframe, or is effectively the player/root surface.
- **Why**: Recovery guidance must remain legible and actionable, while a fake install prompt over a healthy broadcast is both a usability and trust failure. A generic overlay/ad remover would risk destroying the player or the provider's legitimate unmute control, so the nuisance rule is deliberately semantic and narrow.
- **Verification**: Build 29 passed all six Catalyst accessibility audits plus rapid-navigation/foreground recovery. Build 30 passes the complete Swift policy suite, the injected-script JavaScript parse contract, normal and Review Safe iOS Release, and generic-iOS static analysis. The same signed normal artifact is installed on both authorized devices and each independently reports `2.0.0 (30)`. Broadcast 1 decoded and visibly advanced on both without changing source or showing the VPN solicitation; the iPad still displayed the provider-owned `CLICK UNMUTE STREAM` control, proving the filter did not blanket-remove the player prompt. The owner directly confirmed iPad unmute and Pause, a later capture proved Play/resume on the same source, and the owner reported no ticking or duplicate/overlapping audio.

## 2026-08-25: Builds 27–28 make zero-variant playback and catalog timing truthful
- **Decision**: Advance to `2.0.0 (27)` to reject fabricated canonical Echo/Admin URLs and derive `UPCOMING`, `LIVE`, or `AVAILABLE` from kickoff time, then to `2.0.0 (28)` so only the live state says `Watch live`; upcoming and stale/undated entries say `Open broadcast`. Canonical zero-variant synthesis is limited to the provider contracts Fotty actually knows: Hotel, Delta, Golf, and India.
- **Why**: A stale LASK–Celtic Echo entry supplied no variants, yet build 26 invented an `/1` URL, waited roughly 40 seconds on an upstream 404, and labeled the old event live. That was app-created failure and false product copy, not provider unreliability.
- **Verification**: Timing/action and fallback-whitelist regressions pass inside the complete build-28 Swift suite. Normal and Review Safe iOS Release, generic-iOS static analysis, strict deep signature verification, version checks, and exact-artifact installation pass. Both physical devices independently report `2.0.0 (28)`. The stale Echo event now immediately exposes no playable source and says `AVAILABLE · Open broadcast`. A current three-source event decoded and advanced on both devices for more than 60 seconds with no source change; background/foreground preserved Broadcast 1, iPad entered real PiP after native handoff, and termination removed the PiP surface. Manual tap-to-reveal/Pause/Play and audible duplicate/ticking checks remain open; the three remaining Catalyst UI checks are recorded, not waived.

## 2026-08-25: Builds 23–26 close compact density, cold provider routing, and web-player truth
- **Decision**: Advance monotonically through `2.0.0 (23)`–`(26)` as each installed predecessor exposed a distinct physical acceptance defect. Build 23 makes the complete starting XI fit the iPhone Zoomed/Larger Text canvas without scaling the whole UI. Build 24 resolves exact provider catalog route IDs and presents a truthful broadcast-only Match Center after a cold deep link. Build 25 supplies explicit web Play/Pause when a provider renders none and requires kickoff identity before showing a same-team score. Build 26 moves the compact fallback controls to the video edge, fades them after four seconds, and restores them through a non-cancelling surface tap.
- **Why**: Physical evidence showed a 1125×2436 Zoomed canvas, a dead provider-only Match Center, decoded video/audio with no usable transport control, an older Premier League `FT 0–1` leaking into a current cup feed showing `0–2`, and then oversized permanent controls centered over the match. These are product-truth and usability failures that compile-only review cannot reveal.
- **Verification**: Focused regressions cover compact lens labeling, exact catalog identity/fallback, explicit web transport commands, bounded auto-hide, and kickoff acceptance/rejection. Build 26 passes the full Swift suite, both iOS Release configurations, and static analysis. One signed universal normal artifact is installed and version-reported as `2.0.0 (26)` on the physical iPhone and iPad. The prior build physically decoded the current provider with working audio and no premature source change; build-26 control fade/tap/pause/resume awaits reconnection. Four exact-source Catalyst audits pass; the fifth failed once and its rerun was killed before test connection, leaving three UI checks open.

## 2026-08-25: Release evidence cannot consume the workstation
- **Decision**: On the 256 GB/8 GB development Mac, every broad Xcode gate must reuse one DerivedData root and remove owned temporary output on success, failure, or interruption. No simulator is allowed. Explicit caller-provided cache paths are the only retained-cache escape hatch.
- **Why**: Per-build/per-configuration directories accumulated 40 GB under `/private/tmp` (32 GB created the same day) plus Fotty DerivedData, leaving 3.7 GB free. Verification artifacts have no value after their result is recorded and the exact app is installed.
- **Verification**: The generated Fotty directories, DerivedData, and temporary screenshots were removed, restoring 43 GB free. Root agent instructions now encode the workstation limits. `ios-device-qa.sh` and `catalyst-ui-release-gate.sh` use validated cleanup traps; shell syntax, a help-path cleanup smoke, diff hygiene, and a zero-leftover-directory check pass.

## 2026-08-25: Build 22 routes the normal Debug app for physical visual QA
- **Decision**: Advance to `2.0.0 (22)` and add one bounded Debug-only `--fotty-fpl-workspace` argument that initializes Plan, Squad, Coach, or Tools. Keep Release behavior unchanged. Use CoreDevice to launch the signed normal app with the argument and `fotty://fpl`; never install a physical-device UI-test runner or claim that routing proves keyboard/audio/control interaction.
- **Why**: The device screens repeatedly auto-locked while waiting for manual taps, leaving the build-21 compact Squad correction physically uncaptured. A normal-app route makes form-factor evidence repeatable in the narrow unlocked window without synthetic touch automation and remains useful for future physical visual regression checks.
- **Verification**: The allowlisted parser accepts separate and inline arguments, maps Plan/Gameweek, Squad, Coach, and Tools, and rejects unknown values in a focused regression. Build 22 passes 94 Swift tests plus one intentional soak skip with zero failures/runtime warnings, signed/strictly verified Debug and Release builds, Review Safe compile, generic iOS static analysis, all six Catalyst accessibility audits, and rapid-navigation/foreground recovery. A fresh Catalyst runner timed out before testing; the already-authorized release runner then executed the exact build-22 source at 7/7. The same verified Debug artifact is installed and version-reported as `2.0.0 (22)` on both devices. Physical build-22 holds and routed captures await unlock.

## 2026-08-25: Builds 18–21 turn two-device visual review into release evidence
- **Decision**: Advance monotonically through builds 18–21 as each predecessor reached hardware and revealed a distinct truthful-copy or form-factor defect. Build 18 replaced substring score-coverage matching with an explicit senior Premier League/Champions League allowlist. Build 19 then removed the remaining team-name league guess when no schedule fixture confirms score coverage. Build 20 distributes the three FPL command-centre metrics across the regular-width row. Build 21 contains compact Squad player cards and formation spacing so a five-player line cannot expand the whole iPhone workspace.
- **Why**: The physical iPad first showed `LIVE · SCORE UNAVAILABLE` for Blackpool–Aston Villa U21, then proved the first policy fix was insufficient because the hero fell back to team-name inference. Later iPad Plan review showed `Current squad` clipped inside three narrow adaptive metric columns despite abundant width. The build-20 iPhone Squad capture showed fixed 76-point cards pushing the shared header and controls beyond both screen edges. None of these defects was acceptable as a daily-use interface, and replacing an already installed build number would destroy traceability.
- **Verification**: Build 21 passes 93 Swift tests plus one intentional live-soak skip with zero failures/runtime warnings, 68/68 web/Worker tests, zero-error lint, optimized Next build, signed Debug/Release, compile-only Review Safe, generic iOS static analysis, shell/plist/whitespace checks, and all six Catalyst accessibility audits plus rapid navigation. A clean universal Debug artifact passes strict deep signature verification and reports `2.0.0 (21)` in the app and extension; that same artifact is installed and version-reported on both physical devices. The exact artifact passes the 60-second iPad hold, while the final iPhone hold awaits unlock. Build-19 Home and build-20/21 Plan captures verify the score-copy and regular-width metric corrections; final build-21 physical Squad/Coach/widget/playback interaction remains authoritative. No simulator or physical-device UI-test runner was used.

## 2026-08-25: Build 17 makes the exhausted-startup boundary truthful
- **Decision**: Advance the candidate to `2.0.0 (17)` rather than replace build 16 after its physical iPhone playback trace exposed an app-owned diagnostics defect. When a non-explicit child-frame provider error is deliberately deferred through the complete startup window and no decoded progress appears, classify the terminal boundary as `Startup timeout: no decoded video within 20 seconds`. Preserve explicit provider-rejection reasons unchanged.
- **Why**: The Abha–Al-Khaleej physical session recorded two same-source attempts about 21 seconds apart, zero decoded starts, zero automatic failovers, and a terminal failure after the second full window. Fotty correctly protected the selected source and the provider failed to decode, but the exported `unknown` failure and generic terminal presentation did not tell the user or operator what had actually happened.
- **Verification**: A focused regression proves opaque deferred failures become `.startupTimeout`, include the 20-second boundary, and leave explicit provider-unavailable signals untouched. The complete no-simulator Swift result is 92 passed, one intentional soak skipped, zero failed, and zero runtime warnings. Signed Debug and optimized Release, compile-only Review Safe Release, generic iOS static analysis, all six Catalyst accessibility audits, rapid-navigation/foreground recovery, 68/68 web/Worker tests, zero-error ESLint, the optimized Next build, version/signature/plist/shell/whitespace checks, empty client API-key fields, and build-bundle credential scans all pass. The signed normal build 17 is installed and independently version-verified on the physical iPhone; it locked before the 60-second hold. The iPad install hit a CoreDevice tunnel timeout and then became unavailable. No simulator or physical-device UI-test runner was used, and final physical interaction remains authoritative.

## 2026-08-25: Build 16 closes two defects found only in the physical compact Home audit
- **Decision**: Advance the integrated candidate to `2.0.0 (16)` rather than replace distributed build 15. Offer MultiView only when at least two otherwise-eligible events are live or within 30 minutes of kickoff; catalog source presence and historical provider success cannot make a broadcast watchable hours early. Preserve recognizable dense club labels with explicit common-name mappings instead of ambiguous first-letter forms.
- **Why**: The physical iPhone Home capture showed a visible `Watch 2` action while its candidate rows were about two hours away, plus `L. City` for Leicester City. Both controls technically rendered and passed automated accessibility checks, but one could not yet deliver its promise and the other forced the user to decode an ambiguous abbreviation.
- **Verification**: Focused timing/name regressions pass, followed by the complete build-16 Swift gate at 91 passes plus one intentional live-soak skip, zero failures, and zero runtime warnings. Signed Debug, signed optimized Release, compile-only Review Safe Release, and generic iOS static analysis pass. All six individual Catalyst accessibility audits plus rapid-navigation/foreground recovery pass on the exact build-16 source. The signed normal artifact installed on both physical devices. CoreDevice independently confirms `2.0.0 (16)` on the iPad; that app survived a complete 60-second foreground hold, and physical Home/FPL captures verified the corrected 64 total, readable `Sheff Wed`, hidden premature MultiView, and no clipping or dock overlap. CoreDevice has also independently re-verified `2.0.0 (16)` on the connected but passcode-locked iPhone, where the final launch hold remains pending. Two current `echo` candidates returned media HTTP 500; the next event's two `admin` broadcasts passed a kickoff-aligned 45-second hold with about 45.3/43.0 seconds of advancement, longest pauses of 0/about 2.0 seconds, HTTP 200 media, zero popup, and zero request failure, establishing a current hardware target. Physical controls remain pending. No simulator or physical-device UI-test runner was used.

## 2026-08-25: Build 15 closes the Mac release gate; physical interaction remains authoritative
- **Decision**: Advance the integrated candidate to `2.0.0 (15)` for the final Dashboard/FPL accessibility corrections. Keep the release status at candidate until the exact normal app passes launch, compact/regular form-factor, provider-control, audio, PiP/Live Activity, notification, and teardown checks on the supported physical iPhone and iPad.
- **Accessibility boundary**: Custom sport and competition menus expose native Picker semantics and selected values; FPL loading copy is one useful announcement; match rows expose complete team labels while decorative crest initials are hidden from assistive technology. Audit handlers stay category-specific so a text-clipping run cannot be failed by a contrast finding, while every category retains its own strict gate.
- **Verification**: The complete build-15 Swift suite passes 90 tests with one intentional live-soak skip, zero failures, and zero runtime warnings. Web/Worker tests pass 68/68; ESLint has zero errors; Next/TypeScript, Debug, optimized Release, Review Safe Release, generic iOS static analysis, project parsing, plist validation, shell/Node syntax, and whitespace checks pass. On an unlocked Mac, all six individual accessibility audits plus rapid-navigation/foreground recovery pass (7/7). The macOS 27 beta accessibility warning is platform-owned and adjacent to missing Apple accessibility support bundles, with no Fotty frame. The exact normal `2.0.0 (15)` app is installed and CoreDevice-version-verified on both physical devices with no Fotty UI-test runner. The iPhone app passed the 60-second foreground process hold; physical captures verify compact Home, visible FPL deep-link routing, an unclipped Plan workspace, and the corrected on-device 64-point total. Squad/Coach keyboard/widget/large-Type, iPad launch, and physical playback remain. No simulator was used.

## 2026-08-25: Build 14 closes native lifecycle gaps without claiming physical acceptance
- **Decision**: Advance the integrated candidate from `2.0.0 (12)` through builds 13 and 14 because each predecessor had already reached the physical iPad before the next lifecycle correction. Keep the release status at candidate until the supported iPhone/iPad and unlocked-Mac gates actually pass.
- **Playback lifecycle**: Standard provider controls remain provider-owned in the foreground. When Fotty backgrounds, the injected monitor suspends reachable video/audio across the provider frame tree and resumes the same attempt on return, eliminating hidden provider/ad audio without treating the lifecycle transition as a source failure. The system toggle-play/pause command now dispatches a real toggle and remote commands are disabled during teardown.
- **Live Activity return**: A Live Activity is created only after AVKit confirms PiP is actually active, never merely because PiP is supported or a generic inactive scene transition occurred. Stop, failure, or availability loss clears the continuity state and pauses native playback if already backgrounded. A `fotty://live/<match>` link reveals the matching player when that player still exists; after process termination, it opens the matching Match Center instead of merely returning to an unrelated tab. A cold app launch still ends orphaned activities; Fotty does not claim that it can observe the instant iOS force-terminates its process.
- **Provider evidence**: The corrected decoded matrix now supports an optional post-start continuity hold. Both numbered feeds in the current playable family decoded and passed a 45-second hold with HTTP 200 media, no request failures, no popups, and no freeze of ten seconds or longer. This satisfies the independent provider/short-continuity gate but not physical controls, audible unmute, native/PiP, interruption, or teardown.
- **Verification**: The injected JavaScript parses under JavaScriptCore, focused lifecycle regressions pass, and the complete no-simulator Swift suite passes 90 tests with one intentional live-soak skip, zero failures, and zero runtime warnings. Normal Debug, optimized Release, Review Safe Release, and static analysis pass for build 14. The signed normal app is installed and CoreDevice-version-verified as `2.0.0 (14)` on the physical iPad; launch remains pending because the iPad and Mac are locked, and the iPhone is unavailable. No simulator or device UI-test runner was used.

## 2026-08-24: FPL scoring is deterministic and cannot be overruled by DeepSeek
- **Decision**: Ship the client correction as `1.8.4 (11)` and deploy the Worker guardrail immediately. Questions about current points, bench replacements, or automatic substitutions bypass DeepSeek after the Worker refreshes official manager picks, event-live stats, fixtures, and bootstrap player positions. The same deterministic resolver drives the iOS Live Points total and local Coach fallback.
- **Rules boundary**: Preserve the official current total as one fact. A different projected total is allowed only when a starter has no appearance and every gameweek fixture for that player is complete, the bench replacement appeared, goalkeeper replacement is goalkeeper-only, outfield bench order produces a legal 3–5 defender / 2–5 midfielder / 1–3 forward formation, captain-to-vice fallback is handled, and transfer cost is deducted. Name every projected replacement and label the result provisional until official `automatic_subs` or a completed data check arrives. LiveFPL is a useful behavior and presentation benchmark—especially its before/after-autosubs split—but is not a Fotty data dependency; Fotty resolves the same class of result from official FPL endpoints.
- **Why**: The previous packet exposed raw official picks and live stats to DeepSeek but did not provide an authoritative computed scoring block. The model could therefore misread a temporarily unprocessed official total as final and contradict valid pending automatic substitutions.
- **Verification**: Swift regression tests reproduce official 50 plus a seven-point bench goalkeeper and seven-point bench defender replacing two completed-fixture non-appearances, yielding a provisional 64. Another proves an earlier midfielder is skipped when a defender is required for legal formation, and final-state tests prevent Fotty from overriding a data-checked official total. Twenty focused FPL tests and five Worker scoring tests pass. Production version `c0a480d9-d966-4926-8931-bb74beebae73` returned an official scoring answer from `Fotty FPL Rules Engine` with zero prompt, completion, and reasoning tokens. The full web suite has 54 passes and one unrelated existing static-route assertion failure. The signed `1.8.4 (11)` app installed and launched on the physical iPad; the iPhone remained unavailable to CoreDevice, so its build 11 installation is pending.

## 2026-08-24: Compact iPhone FPL and Coach keyboard correction
- **Decision**: Ship `1.8.3 (10)` as a focused daily-use correction. Compact-width FPL reduces shell insets, header height, workspace-bar height, grid size, and obsolete bottom reservations; Smart Coach removes its duplicate title in the compact shell. The layout remains semantic and adaptive rather than applying a global scale transform or clamping Dynamic Type.
- **Keyboard behavior**: Smart Coach owns its composer focus explicitly. Send, Return, and quick prompts resign focus before starting a request, and the message list supports interactive keyboard dismissal, so the first response is not left hidden behind the keyboard.
- **Why**: Physical iPhone use showed that desktop/iPad spacing made the FPL workspace feel zoomed in and that clearing the first question did not resign the text field. The global tab shell deliberately ignores the keyboard safe area, so a targeted focus lifecycle fixes Coach without changing keyboard behavior across unrelated tabs.
- **Verification**: Debug Mac Catalyst and generic physical-iOS builds pass, as does the focused 17-test FPL suite. Current official FPL data rendered without clipping in a narrow Catalyst window. The paired iPhone remained unavailable to CoreDevice at deployment time, so physical installation and the final send/reply interaction remain an explicit acceptance check. No simulator or UI-test helper was used.

## 2026-08-24: FPL becomes a decision workflow, not a collection of tools
- **Decision**: Ship the next five FPL improvements together as `1.8.2 (9)`: a Rival Race Centre, structured Smart Coach cards, Transfer Lab route comparison, a manager-scoped Decision Journal, and a minimal FPL deadline widget with accessibility/presentation cleanup. Keep the product boundary honest: rival squads appear only after publication, transfer changes remain local drafts, journal content stays on-device, modeled gains remain labeled, and the widget has no manager identity or live-score claim.
- **Why**: The existing engines already had useful official facts and calculations, but the UI flattened explanations, hid tradeoffs, and scattered related actions. The useful next level is a repeatable loop—compare the race, review evidence, choose and validate a route, record the reasoning, then review the outcome—without pretending Fotty can write to the official account or see private rivals.
- **Smart Coach boundary**: DeepSeek remains the opt-in remote reasoning layer through the production Worker; it was not removed. The client now preserves the validated structured response as recommendation, confidence, evidence, downside/limits, verify-before-deadline checks, source/model, and official-data freshness. The deterministic local fallback maps into the same presentation and legacy unstructured history remains decodable.
- **System/data boundary**: Rival Race uses the already-loaded official standings, published picks, current fixtures, and event-live snapshot; it does not invent effective ownership, live overall rank, or private pre-deadline squads. The WidgetKit extension refreshes the minimal public bootstrap contract on a system-managed timeline no more often than hourly and deep-links to the FPL tab.
- **Verification**: Debug Mac Catalyst and generic physical-iOS builds compile with the widget embedded. The focused no-simulator FPL suite passes, including new journal isolation/update, legacy coach-history, Transfer Lab route-check, and Rival Race official-data regressions; the full unit-only Catalyst gate passes 57 tests with the intentional playback soak skipped. The signed app and embedded extension both report `1.8.2 (9)`. That exact normal app is installed on the physical iPad and iPhone 15 Pro Max and launched successfully on the iPhone; CoreDevice could not launch it on the iPad only because the iPad remained locked. Mac Catalyst loaded current official FPL data, displayed the new Tools grid and Transfer Lab, and accepted the `fotty://fpl` deep link. No simulator or UI-test helper was used.

## 2026-08-24: Matchday OS begins with one shared FPL match context
- **Decision**: Rename the consumer tab from `Matches` to `Matchday` while retaining its legacy persisted raw value, make the FPL primary workspace read `Plan`, `Live`, or `Review` from the verified gameweek phase, and publish one expiring device-local squad snapshot after the existing FPL workspace loads. Home cards, Matchday, and Match Center may read that snapshot but may not create another FPL network owner.
- **Why**: Football discovery and FPL planning should reinforce each other. A user should immediately see why a fixture matters to their squad, while the app avoids hidden polling, duplicate requests, and claims that a local draft is an official FPL submission.
- **Product behavior**: Relevant cards show starter/bench/captain involvement; FPL-related fixtures automatically join My Matchday; Match Center exposes an FPL Match Lens with captain/vice-captain, lineup role, and official live points/minutes when those facts were already fetched. The context clears on manager removal/change and expires after 21 days.
- **Verification**: The no-simulator Debug Catalyst build passed. The unit-only Catalyst gate passed 53 active tests with one intentional soak skipped; a final focused run passed all 13 FPL tests, including deterministic planning metrics, persisted squad-to-team matching, manager clearing, and expiry. Build 7 was installed during verification, then the Matchday header audit caught stale two-source copy; professional monotonic versioning advanced the corrected artifact to `1.8.1 (8)`. The signed app and Live Activity extension both report build 8, and that exact app installed and launched on the physical iPad. The cabled iPhone remained unavailable to CoreDevice's trusted-connectivity service. The beta Xcode optimized Release compiler remained active without a source diagnostic for more than 12 minutes and was deliberately stopped, including its child frontend, to avoid monopolizing the Mac. No simulator or UI-test helper was used.

## 2026-08-24: 1.7.2 separates Home scheduling from My Matchday history
- **Decision**: Home `Match schedule` shows only live and upcoming fixtures. Finished catalog events are filtered from Home as soon as official status reports completion or the bounded no-score kickoff heuristic proves the match is over. The shared 36-hour retention remains intact so saved or followed fixtures can appear under `Matches → My Matchday → Recent` with final context.
- **Why**: Retention and presentation had been conflated. Finished matches were ranked last but still appeared beneath a schedule heading, making completed content look upcoming and weakening the distinction between broad Home discovery and personal matchday history.
- **Verification**: Added a policy test proving a four-hour-old completed fixture still passes catalog retention but is excluded from Home while in-play and upcoming fixtures remain. The focused no-simulator Catalyst policy gate passed 33 active tests, and the full unit-only gate passed 51 active tests with the intentional soak skipped. Version advanced to `1.7.2 (6)`; the signed main app and Live Activity extension both report that version, but both physical devices were unavailable to CoreDevice for installation.

## 2026-08-24: 1.7.1 restores provider-owned web controls
- **Decision**: In the standard live player, the WKWebView and provider own play, pause, seek, fullscreen, and `Tap to unmute`. Fotty observes decoded progress and blocks popup/ad navigation but does not wrap the web surface in an app tap gesture, render a duplicate unmute button, remove the provider prompt, or continuously force media mute/volume. MultiView and explicit muted diagnostics remain the only app-controlled web-audio cases.
- **Why**: The 1.7.0 audio intervention introduced two user-visible regressions: the parent SwiftUI tap gesture captured the whole player surface, and a 500-millisecond synchronization loop immediately remuted media after the provider's own unmute gesture. A DOM property change alone had not proven interactive behavior.
- **Implementation**: Added an explicit provider-controlled audio mode to `LiveWebEmbedPlayerView`, scoped Fotty's tap-to-show-controls gesture to native AVPlayer only, removed standard-player audio state and duplicate UI, and stopped deleting provider mute prompts. Native handoff still unmutes normally outside muted automated tests.
- **Verification**: Version advanced to `1.7.1 (5)` rather than replacing distributed build 4. The no-simulator focused Catalyst playback suite passed 32 active tests, and the full unit-only gate passed 50 active tests with the intentional soak skipped. The signed main app and Live Activity extension both report build 5; the artifact installed, launched, and reports `1.7.1 (5)` on the physical iPhone 15 Pro Max. The paired iPad remained unavailable to CoreDevice. Final provider-control and audible acceptance still requires a currently decoding physical-device stream.

## 2026-08-24: Rebaseline at 1.7.0 (4); Fotty-owned web audio superseded by 1.7.1
- **Decision**: Establish `1.7.0 (4)` as the one-time Daily Driver Beta baseline across the app and Live Activity extension. From this point forward, use semantic marketing versions, monotonically increasing build numbers, `tools/set-version.sh`, `CHANGELOG.md`, and `docs/RELEASE-PROCESS.md`; never treat a CoreDevice installation sequence as the app build.
- **Superseded audio behavior**: Build 4 attempted to make Fotty authoritative for web unmute. Physical use showed that decision intercepted provider controls and re-muted media, so 1.7.1 removes it. The versioning rebaseline remains valid.
- **Why**: The provider could replace or nest its video after Fotty's one-time main-document mute update, leaving a stale provider prompt or a genuinely muted child-frame video. Version `1.6 (3)` also no longer represented the accumulated daily-driver feature set and lacked a repeatable release discipline.
- **Verification**: The focused no-simulator Catalyst playback-policy suite passed 32 active tests, and the full unit-only gate passed 51 tests with the intentional two-minute soak skipped. A WebKit provider probe changed the actual video from `muted=true, volume=0` to `muted=false, volume=1`. The signed main app and extension both report `1.7.0 (4)`, and that artifact installed and launched on the physical iPhone 15 Pro Max. The paired iPad was unavailable to CoreDevice during installation. Audible output remains a manual physical-device acceptance check on an actively decoding source; no simulator or device UI-test helper was used.

## 2026-08-24: Home `LIVE` is a watchability promise
- **Decision**: On Home, reserve the `LIVE` label for catalog events that advertise a supported web broadcast and make the entire row open playback. A score/schedule fixture that is underway without a supported catalog source is labeled `IN PLAY` and opens details instead. Recent provider-family failures may change automatic source ordering, but cannot hide Watch or block the first source attempt after an explicit user tap.
- **Why**: Match timing and broadcast capability had been conflated. Eight of the current eleven catalog-live matches were `echo`-only; Fotty displayed them as `LIVE` while excluding that family from playback, leaving rows that looked watchable but behaved like dead controls.
- **Implementation**: Restored current StreamEx catalog families (`admin`, `delta`, `echo`, `golf`, and `india`) to the supported web pipeline, kept `hotel` under Score808, added a Details fallback for genuine non-broadcast rows, and made initial single-player loading honor manual intent over the automatic circuit breaker.
- **Verification**: The current catalog was inspected directly, Debug Mac Catalyst compiled, and 28 playback-policy tests passed with one opt-in soak skipped. The Catalyst app showed Watch on the formerly dead `echo` rows and a full-row interaction opened the Fotty player with two numbered broadcast sources. That sampled provider feed then returned upstream HTTP 503/404 responses and did not decode, correctly surfacing a playback error rather than being hidden by Home. The signed build installed and launched on iPad sequence `2224` and iPhone sequence `2372`; a physical-iPad screenshot confirmed every visible `LIVE` row exposes Watch. No simulator or UI-test runner was used.

## 2026-08-24: Matchday Editorial is the single consumer UI system
- **Decision**: Replace the accumulated dashboard/control-center presentation with one restrained matchday hierarchy and shared semantic type, surface, border, and button tokens. The persistent product navigation is `Home`, `Matches`, `FPL`, and `Settings`; the legacy `Arena` raw tab value remains only as a persistence migration detail.
- **Home and matches**: Home now has one compact `Now & next` lead match and one chronological `Match schedule`, rather than several overlapping live/soon/team rails. `Matches` owns the literal `Live`, `Upcoming`, and `Results` states with competition filtering and status-aware score/time rows. Scheduled fixtures never render a misleading 0–0. Score coverage is deliberately Premier League-only, so an active non-covered league does not show a score-unavailable message. The later Home-watchability decision reserves `LIVE` for rows with a supported catalog broadcast and uses `IN PLAY` otherwise.
- **Match Center and player**: Match Center is one status-aware overview instead of Arena/Insights/Highlights tabs. It shows lineups and insights only when data exists, reserves space for its own consistent close control, and offers a real retry when details are unavailable. The player has one portrait match header, opaque loading/error states, compact numbered broadcast rows, generic quality descriptions, and truthful `Selected`, `Select`, or `Try again` actions. Internal provider names, heat, risk, cooldown, and discovery diagnostics stay out of consumer UI.
- **FPL and settings**: FPL is organized into four stable workspaces—`Gameweek`, `Squad`, `Coach`, and `Tools`—while preserving the existing official-data and Smart Coach engines. Settings is local-first and grouped by Preferences, Notifications, Playback, Privacy, and About; dead cloud/account controls and duplicated profile actions are removed.
- **Verification**: Final Debug Mac Catalyst compiles and was visually checked across Home, Matches, FPL, Settings, and player recovery. The no-simulator policy gate passed 46 tests with one opt-in soak skipped. The final signed build installed and launched on the connected iPhone 15 Pro Max as installation sequence `2364` and on the connected iPad as sequence `2216`. A physical-iPad screenshot confirmed the masthead respects the status bar and non-covered live competitions show `LIVE` without a false score-error message. No simulator, UI-test runner, or helper app was used. The generic Release smoke was interrupted after the iOS 27 beta Xcode build operation hung during package loading; it produced no source diagnostic. Live-provider/PiP behavior still requires an active compatible stream and manual physical-device interaction.

## 2026-08-23: Official FPL fixtures are the primary Premier League score source
- **Decision**: Reuse Fotty's existing official public FPL `fixtures/` and `bootstrap-static/` transport for Premier League scores. Map only actively playing fixtures, merge them into football-data schedule identities using shared team aliases, label the source `Official FPL`, and poll at 60 seconds only inside the existing match window. API-Football and football-data remain second and third sources respectively.
- **Why**: This gives the personal build useful current-season scores without paying for a feed or spending the restricted API-Football allowance. It uses a data surface the app already trusts instead of adding a second scraper maintenance path.
- **Scraper boundary**: Scraping is still a valid small-app option for a concrete missing field. The reviewed Premier-League-API repository is reference material only: Fotty does not copy its currently unlicensed code, and its present OneFootball selectors returned no rows. Add a server-side scraper only when it fills a measured gap and has freshness, schema, and fallback checks.
- **Freshness and identity**: FPL fixtures cache for 45 seconds, the repository cache for 55 seconds, and stale disk fixture snapshots are rejected. FPL ids are never treated as API-Football ids; live score/status/minute data is merged onto the existing schedule fixture so navigation, notifications, Match Center, and stream matching remain stable.
- **Verification**: The live FPL fixtures and bootstrap endpoints returned HTTP 200, 380 fixtures, 20 teams, and the expected live-state fields. The no-simulator Catalyst gate passed 46 tests with one opt-in soak skipped, and the generic Release build succeeded. No match was active during the probe, so actual match-time latency must be observed during the next Premier League fixture.

## 2026-08-23: Live-score quota is Premier League-only and globally budgeted
- **Decision**: Keep schedules and stream discovery broad, but constrain every live-score/enrichment path to the Premier League. For one active competition, API-Football uses league `39` plus current season/date and filters the response to in-play statuses because the provider rejects a lone id in `live`; football-data fallback uses only competition `PL`; iOS filters provider responses, schedule-derived score UI, minutes, and alerts; non-covered Match Hub rows do not trigger API-Football detail calls; and the emergency fixture fallback follows the same allowlist. The schedule refresh runs first and suppresses the live request outside the five-minute pre-kickoff through three-hour match window. One Worker Durable Object shares a four-minute response cache across devices, caps upstream use at 80 calls per UTC day, and holds the provider's final 20 free-tier calls in reserve.
- **Why**: Fotty should spend its small provider allowance where users are most likely to receive complete, trustworthy data. A worldwide live feed was unnecessary, and the prior multi-league emergency sweep could create several extra calls during an upstream outage.
- **Client reuse and truth labeling**: A successful live-list payload seeds the Match Hub cache. Automatic and timer-driven Match Hub loads reuse known schedule/live data and cannot enrich; only an explicit full refresh may call deeper provider data. A football-data fallback is labeled `Delayed`, and quota reservation is distinct from ordinary provider failure.
- **Future Champions League switch**: The policy records API-Football league id `2` and football-data code `CL`, but leaves them inactive. Adding `.championsLeague` to the active list enables the provider's valid multi-league `live=39-2` form and both providers' UCL ids without reopening global coverage.
- **Verification**: Forty-four active Catalyst tests pass with one opt-in soak skipped; the generic physical-iOS Release build, Worker JavaScript syntax, Wrangler dry run, Durable Object health and access-restriction paths, and production football-data fallback pass. Worker version `e50e0d24-b700-4ca5-9b6e-f178fbca278b` is deployed. A signed normal Debug app was installed on the connected iPhone as installation sequence `2316`. No simulator or UI-test runner was used.
- **Activation boundary**: The production `API_FOOTBALL_KEY` is correctly named and accepted, but the provider explicitly rejected the current 2026 season on its free plan and offered only 2022–2024. Health separates `apiFootballCredentialConfigured=true` from `premierLeagueLiveScoresConfigured=false`; the Durable Object holds that plan restriction for four hours so clients immediately fall back without repeated upstream calls. Current-season minute enrichment requires a provider plan that includes it. Until then football-data is the intentionally labeled delayed score source.

## 2026-08-23: Native-first playback and one daily-use product flow
- **Decision**: Keep provider WebKit playback as the immediate compatibility path, then capture the real HLS/MP4 request only after decoded progress, validate and pre-roll it through a separate muted `AVPlayer`, and switch invisibly only after native time advances. Native failure returns to the same web source before any provider failover. A single `LivePlaybackState` now derives loading/playing state so overlapping callbacks cannot claim contradictory UI states.
- **Why**: Headless extraction before playback was slow and unreliable, while web-only playback prevented dependable Picture in Picture. The visible stream must never be sacrificed for a speculative native upgrade.
- **Product consolidation**: Watch shows compact numbered broadcasts and visible playback notices; Search, Home, and Arena converge on one Match Center; unverifiable `4K`, provider-heat, and vague data-quality labels are gone. Home explicitly separates Live now, Starting soon, Your teams, and the dated schedule. FPL opens on its phase-aware Gameweek Plan and Smart Coach replies include evidence, limits, confidence, source, official-data status, and verification time.
- **System surfaces**: Match alerts are limited to followed teams whose per-team bell is enabled, and tapping one opens that match in Match Center. A `fotty://live/<match>` Live Activity tap only foregrounds the surviving player instead of covering it with another screen. Live Activities still require verified native/PiP eligibility and clear on close/cold launch.
- **Verification**: Debug Mac Catalyst and generic iOS compile; 36 focused tests pass with the opt-in playback soak skipped; Release and Review Safe generic iOS compile; signed Debug installed and launched as the normal `com.jelani.Fotty` app on the connected iPhone (installation sequence 2300). No simulator, UI test, or UI-test runner app was used. The iPad was not available to Xcode during this final install and still requires the printed physical checklist.

## 2026-08-23: Live Activities must represent real continuing playback
- **Decision**: Do not create a Live Activity for StreamEx/Score808 web embeds. Present one only after native playback is ready and Picture in Picture/background continuity is actually available. Eligible activities show matchup, score, minute/status, and an explicit return-to-player cue instead of provider diagnostics.
- **Why**: The previous activity started during loading, survived some force-close/background paths, and displayed technical state without useful match context. A system-hosted notification that outlives a web player falsely implies the stream is still running.
- **Lifecycle**: End the activity when playback stops, errors, loses background/PiP eligibility, or leaves the player. Clear orphaned Fotty activities on cold launch; use a short iOS background task so an end request can finish after the scene backgrounds.
- **Verification**: Three focused policy tests pass on Mac Catalyst, the Live Activity extension and signed generic iOS build succeed, and the clean app-only build was installed and cold-launched on the connected iPhone. No simulator or UI-test runner was used.

## 2026-08-23: Watch actions must be source-backed and consumer source UI stays literal
- **Decision**: Only fixtures advertising a supported StreamEx/Score808 catalog source receive Watch actions or enter the hero/On-now/"Pick for me" surfaces. Score-only fixtures remain visible with Details. The player uses compact numbered source rows labeled Playing, Select, or Try again; provider health jargon remains internal.
- **Why**: A physical-iPhone test reproduced a hero "Watch Live" button that could only end in "Stream Not Available." Consumer controls must state a real capability and make their result predictable.
- **Verification**: A subsequent source-backed physical iPhone run opened the live player, found two compact broadcast-source controls, and stayed open without the playback error overlay for 20 seconds.

## 2026-08-23: Score credentials live at the Worker boundary
- **Decision**: iOS football-data calls default to `/api/football/matches` on the production playback Worker. The Worker owns `FOOTBALL_DATA_API_KEY`; optional live/minute enrichment uses `/api/football/live` only when `API_FOOTBALL_KEY` is configured there. The later Premier League-only decision above supersedes this entry's original global-live scope.
- **Why**: The device had no local football credentials, producing `unauthorized` / `noAPIKey` and an empty score index. Provider secrets must not be embedded in the application.
- **Verification**: Worker version `ce02b53b-ead3-46d2-aacf-9d7090758f9b` deployed; health reports schedule configured and global live unconfigured, and the schedule proxy returns a successful authenticated response.

This document tracks technical and product decisions to ensure all agents (Cursor, Codex, Antigravity) maintain consistent reasoning.

## 2026-08-23: Mac Catalyst is the repeatable shared playback laboratory
- **Decision**: Keep iPhone/iPad as the release authority, but use the Mac Catalyst app for sustained testing of the shared native player, required-header local proxy, readiness observation, watchdog, attempt identity, and failover policy. DEBUG Settings → Stream pipeline checks now exposes a two-minute muted continuity soak and an exportable result.
- **Why**: The iOS 27 beta XCTest host can pause or terminate media after a short foreground window, while Catalyst can hold the same production playback objects active for long, repeatable runs without a simulator. Catalyst must not issue iOS orientation geometry requests.
- **Verification**: The signed Debug Catalyst build launched normally. The opt-in soak decoded 120.83 seconds across 120/120 advancing samples at rate 1.0, with zero waiting samples, paused samples, errors, source/attempt/item replacements, or automatic failovers. The actual app then opened current StreamEx #1 playback for New England–NYC and visibly advanced from match clock 68:14 to 71:17, including a period where Fotty lost focus, without returning to loading, showing an error, or visibly changing sources. The ordinary 30-test unit suite passed with the opt-in soak skipped, and `ReviewSafeDebug` Catalyst compiled. A broad Catalyst UI run separately found four Dashboard accessibility-audit failures unrelated to the player edits; these do not invalidate playback but remain Mac UI work.
- **Boundary**: The reference HLS run proves Fotty does not drop a healthy native stream on its own, and the real StreamEx hold proves one current provider embed can remain decoded in the Catalyst app. Neither replaces final iPhone/iPad autoplay, audio-session, background, and WebKit checks during a live match, nor guarantees future StreamEx/Score808 availability.

## 2026-08-23: Playback recovery favors the current decoded stream over eager failover
- **Decision**: Treat a temporary pause or AVPlayer error-log entry as recoverable until bounded progress checks prove the active attempt is still stalled. Every load has a unique attempt ID, and delayed WebKit, AVPlayer, watchdog, foreground, and P2P callbacks must match both the selected source and that exact attempt before they can change state or trigger failover.
- **Why**: A provider stream could briefly stall, recover and resume visibly, then be replaced by an automatic source attempt that had been scheduled from stale failure evidence. Source identity alone was insufficient when the same source had been reloaded.
- **Web behavior**: Web playback now waits 30 seconds without decoded playhead progress, accepts a recovery signal during a final eight-second grace period, cancels the pending failure when progress resumes, blocks popups/top-level ad navigation, and removes known nuisance ad overlays where WebKit can safely reach them. Same-origin or provider-inserted video ads cannot be guaranteed removable without risking the stream.
- **Continuity hardening**: A network-path loss no longer pauses or rebuilds the player, clears source history, or jumps back to a preferred source. Fotty preserves the exact attempt, lets AVPlayer/WebKit buffer, resumes that same item after connectivity returns, and only reloads the selected source if the item is terminally failed. MultiView likewise preserves web attempts across background/foreground transitions. All post-start WebKit failure signals now receive an eight-second decoded-progress recovery window, not only errors whose text says `stalled`. The local HLS proxy no longer POSTs per-request telemetry to the retired P2P host; proxy diagnostics remain on-device so logging cannot compete with media traffic.
- **Product UX**: Removed the Safari/provider-site escape and consumer-facing `Risky`, `Reliable`, `Stable`, and `Cooling down` labels. Historical source health and the 15-minute family circuit remain internal inputs to automatic ordering; failed sources are shown simply as unavailable or manually retryable.
- **Verification**: The generic physical-iOS build and signed iPhone build pass. Eighteen focused playback-policy tests pass on Mac Catalyst with no simulator, including stale same-source callbacks, offline attempt preservation, and recovery state. An opt-in muted physical-iPad HLS check decoded Apple reference media and held the same source, attempt ID, and AVPlayer item with zero errors or failovers; longer physical XCTest holds are limited by the iOS 27 beta test host's media/runner foreground window. The signed app was installed and launched successfully on the connected iPhone and iPad.

## 2026-08-23: Production Smart Coach favors verified evidence and bounded output over hidden reasoning
- **Decision**: Run the production `deepseek-v4-flash` coaching call in non-thinking JSON mode. The Worker supplies the whole-decision structure through compact official evidence and explicit truth rules, rejects empty, incomplete, or known rule-contradicting output, and returns non-sensitive token usage for cost monitoring.
- **Why**: Thinking mode consumed the entire 1,400-token and then 3,000-token completion budgets as hidden reasoning, returning no usable answer. Non-thinking mode completed a structured response in seconds and cost less. The first successful answer also exposed ambiguous raw fields, so global gameweek counters were removed, current/next events were compacted, and verified transfer/sell-on/price-projection semantics were added.
- **Truth guardrails**: Four extra free transfers means five total; sell-on fee `0.5` is the half-profit share rather than a fixed £0.5m charge; a price projection is directional rather than realized profit; zero minutes is not evidence of omission before the player's fixture starts. Known contradictions fail closed to the on-device coach.
- **Production verification**: The live Worker returned HTTP 200 with `officialDataStatus=fresh`, valid answer/evidence/assumptions/actions, `finishReason=stop`, and the correct next deadline. The no-manager smoke used 8,982 cache-miss input tokens and 305 output tokens (about $0.00134). Compacting public manager/history/picks data removed irrelevant profile/league fields and reduced a representative manager call from 19,979 input tokens/$0.00297 to 13,787 input tokens plus 564 output tokens/$0.00209, roughly 30% cheaper.

## 2026-08-22: FPL daily-use platform and consent-gated Smart Coach
- **Decision**: Make the FPL area one phase-aware decision system rather than a collection of disconnected advisory screens. Official FPL facts feed a shared command center, live tracker, player evidence, rival analysis, planner, squad validator, optimizer, reminders, and confirmed-gameweek review. AI explains that evidence but does not manufacture it or replace the local rules engine.
- **Smart Coach architecture**: Keep a deterministic on-device fallback. With explicit in-app consent, send only the question, up to eight recent messages, manager ID, and a compact decision context to Fotty's Cloudflare Worker. The Worker independently refreshes official FPL evidence and calls DeepSeek with a server-held secret; no AI credential is stored in the iOS bundle.
- **Truth boundaries**: Official, modeled, stale, and local-draft data are labeled separately. Event-live points/BPS/bonus and autosubs come from official endpoints. Available free transfers remain a public-history estimate, selling prices are not guaranteed by the public API, and transfer/wildcard actions remain local drafts rather than official submissions.
- **Implementation**: Added snapshot provenance and freshness, phase detection, shared formation/budget/club/captain/selectability validation, official live refresh, post-GW review persistence, transfer-route comparison across five or eight gameweeks, legal safe/balanced/aggressive squad generation with locks/exclusions, price-direction evidence, deadline reminders, deeper player comparison, and live rival swings. Replaced unsupported EO/rank/Monte Carlo/exact-ILP claims and removed dormant fake-data engines.
- **Verification**: Eleven focused FPL contract/rules/validation tests pass within the full 25-test suite. Debug and Review Safe Catalyst builds pass. The Worker packages successfully in Wrangler dry-run mode.
- **Activation status**: The correctly named Worker secret and route were deployed and production-smoked on 2026-08-23. The app still falls back locally for unavailable, over-limit, empty, malformed, or verified-rule-contradicting provider output.

## 2026-08-22: FPL must be official-data-first and truth-labeled
- **Decision**: Treat the present FPL feature as an ambitious prototype, not a decision-safe daily-use tool. Before adding more surface area, remove client AI secrets, restore current official API compatibility, centralize squad legality, and distinguish official facts, modeled projections, and editorial/AI explanations in both types and copy.
- **Why**: The audit found a live league schema mismatch, deadline-independent “pre-season” transfer costing, fabricated or heuristic live bonus/rank/EO/price values, misleading local-only transfer actions, a greedy optimizer presented as an exact ILP, hardcoded tactical claims that contradict the live player catalog, and no FPL-specific tests or accessibility semantics.
- **Product direction**: Use the free official FPL surface more deeply rather than adding a licensing provider. Build one phase-aware Deadline Command Center: pre-deadline planning, true event-live tracking during matches, and post-gameweek review. Add mini-league rival swings and explainable AI only after the underlying facts and rules are trustworthy.
- **Required validation**: Contract-test every consumed official endpoint; test deadline, rolling-transfer, two-chip-set, blanks/doubles, squad formation, budget, club quota, captain/vice, and autosub rules; show cache age/source; and never describe a local draft as an applied official transfer.
- **Trust-reset implementation**: Removed embedded AI credentials and all FPL coach network calls; coaching is now deterministic and on-device. Updated mini-league decoding for the current `entry`, `player_name`, `league_type`, and paging contract; prefers private mini-leagues and exposes loading, retry, empty, and load-more states. GW1 unlimited transfers now depend on the official deadline. Manager drafts and chat are manager/season scoped, purchase/selling prices survive mutations, and local transfer/wildcard/recommendation surfaces are explicitly labeled as drafts or Fotty model output.
- **Removed claims**: The product no longer reconstructs live points, bonus, autosubs, effective ownership, rank movement, Monte Carlo outcomes, press-conference certainty, exact ILP optimization, or hardcoded unlocked achievements from unsupported heuristics. The static tactical/pre-season registry no longer affects advisor scores.
- **Verification**: Added five focused FPL contract/rules tests. All 19 unit tests pass, and normal Debug plus `ReviewSafeDebug` simulator builds succeed. Source secret scanning and a live league-contract probe pass. Previously exposed provider keys still require revocation outside the repository.

## 2026-08-22: Daily-use playback means adaptive degradation, not guaranteed provider uptime
- **Decision**: Keep the existing third-party catalog model and make Fotty resilient around it. Web playback now preserves the provider page for a browser-parity startup window, proves success only from decoded/advancing video, delays child-frame errors until the startup deadline, fails over automatically, and opens a 15-minute family circuit after two consecutive failures. Manual retry always remains available.
- **Why**: A commercial licensing/feed API is not a realistic dependency for this project, while pretending an iframe load is a working stream causes black screens and retry loops. The app can control selection, validation, recovery, and honesty; it cannot control upstream rights or manifests.
- **Recovery UX**: Broadcast Sources is a real sheet again, cooling/failed sources are labeled and manually retryable, and the terminal player offers the provider website in Safari. MultiView is only offered after at least two candidates exist and their provider family has produced a decoded success in the last 24 hours.
- **Measured result**: `tools/audit_live_playback_matrix.mjs` sampled 24 current variants across admin, delta, echo, and golf with WebKit. Result was 0/24 decoded: admin/delta/echo manifests returned HTTP 403/CORS and golf reported embedding disabled; no current hotel candidates were listed. This is provider availability evidence, not an app regression.
- **UI/accessibility**: The custom dock now participates in layout instead of covering scroll rows; fixture rows use concise team/time labels; contrast, Dynamic Type, element detection, hit-region, clipping, trait, and element-description audits pass as bounded tests.
- **Verification**: 14 unit tests pass; rapid navigation/background recovery passes; normal physical-iOS, Review Safe, and static-analyzer builds pass. Signed device installation sequence `2064` rendered, refreshed 220 cached fixtures to 254 current fixtures, and survived a console-attached 65-second physical-iPad hold before an intentional interrupt.

## 2026-08-22: iOS stabilization baseline and honest feature scope
- **Decision**: Treat the current iOS product as a live-sports companion with local profiles/social data, provider-backed match discovery, and optional StreamEx/Score808 web playback. Remove unimplemented PocketBase account claims, fake seeded activity/content, VOD placeholder surfaces, and user-facing P2P/AceStream paths.
- **Why**: Daily-use reliability requires the UI to describe capabilities the shipped app can actually perform. Placeholder success states and retired infrastructure made failures look like working product behavior.
- **Implementation**:
  - Playback resolution is cancellation-safe, bounded to 20 seconds, filtered to the two enabled module families, and fails over between independently validated candidates.
  - `LiveWebEmbedPlayerView` reports decoded-frame progress, startup timeout, stalls, blocked navigation, and provider errors instead of treating page load as playback success.
  - Social messaging and profiles are explicitly on-device; Highlights exposes real match context and does not invent video clips; FPL requires a real manager ID/API response.
  - App and extension plist permissions were reduced to capabilities in use. Review Safe excludes the complete playback implementation through `APP_REVIEW_SAFE` substitutions.
- **Verification**: Normal and Review Safe generic simulator builds and the Xcode static analyzer succeed; this baseline was subsequently expanded by the daily-use playback decision above.

## 2026-08-22: Playback availability is measured at decoded video, not catalog health
- **Decision**: Keep catalog/provider health separate from playable-video health. A source is not reported healthy merely because the Nexus catalog or embed document returns HTTP 200.
- **Why**: All three current catalog feeds returned roughly 300 events, while real browser probes of sampled live matches produced no decoded frames: the StreamEx admin/delta manifests were blocked with HTTP 403/CORS and the golf candidate exposed an ad/no video.
- **Consequence**: The iOS failure and fallback UI is working, but current third-party live video availability remains an infrastructure dependency. Do not describe playback as end-to-end working until a decoded-frame probe succeeds.

## 2026-08-22: Automated tests must not start production polling
- **Decision**: `AppRuntime.isAutomatedTesting` gates dashboard/live-score polling, and the shared Fotty scheme sets `FOTTY_AUTOMATED_TESTING=1` for test actions.
- **Why**: Unit-hosted app launches were making live network requests, creating non-deterministic tests and unnecessary provider traffic.
- **Verification**: The isolated iPad unit run completed 10/10 with no production match requests in the log.

## 2026-08-22: iOS Cold-Launch Observation Loop Fix
- **Decision**: Keep `LiveScoreService`'s derived match indices and lookup caches outside Swift Observation, and represent negative lookups with a dedicated set instead of assigning `nil` to a dictionary subscript.
- **Why**: The physical iPad termination report proved a `scene-create` watchdog (`0x8BADF00D`), with the main thread stuck flushing `ObservationGraphMutation` during the first SwiftUI commit. Dashboard view evaluation called `findMatch` repeatedly; its observed cache writes invalidated the same view graph, while `matchLookupCache[key] = nil` removed misses instead of caching them.
- **Implementation**:
  - Marked the match indices, positive-result cache, and negative-result set with `@ObservationIgnored`.
  - Removed redundant locks because `LiveScoreService` and `findMatch` are main-actor isolated.
  - Clear both positive and negative lookup caches when refreshed match data rebuilds the indices.
- **Verification**:
  - Reproduced the previous installed build dying at about 30 seconds after loading 306 cached matches.
  - Built and signed Debug for iOS, installed device database sequence `1984`, and cold-launched on Jet iPad (`00008101-001954E20AC0001E`).
  - The app survived more than 80 seconds with the console attached, refreshed from 306 cached matches to 319 current matches, and rendered the complete Dashboard.
  - Relaunched without the console, captured the rendered dashboard, and confirmed both the app and Live Activity extension processes remained alive.

## 2026-08-14: Formal Homelab Decommissioning & Pure Cloud/Web Architecture
- **Decision**: Removed all residual local homelab fallbacks (`homelabAPIURL`, `homelabMatchesMirrorURL`, blocking SSH sync in agent scripts).
- **Why**: Homelab infrastructure has been retired. Fotty operates 100% cloud-native via edge CDNs, live provider APIs (StreamEx / VipLeague / Score808), and companion web infrastructure. Removing homelab timeouts eliminates 2.5s network delays across dashboard refreshes and tool scripts.

## 2026-08-13: Eliminate Fake Score808 Synthesized Stream URLs
- **Decision**: Restricted `ensureScore808EmbedSessions` in `HybridStreamProvider.swift` to only generate Score808 `hotel` streams when the match descriptor actually contains a legitimate `hotel` source code.
- **Why**: The app previously took IDs from other providers (`echo`, `delta`, `golf`) and synthesized fake `embed.st/embed/hotel/...` URLs. These non-existent IDs caused JW Player to fail loading the HLS manifest with `hls:networkError_manifestLoadError`. Real provider streams are now preserved without synthetic corruptions.

## 2026-08-13: JW Player Direct API Autoplay & Ad Overlay Bypass
- **Decision**: Added direct `window.jwplayer` API integration (`jw.skipAd()`, `jw.play()`) and automatic ad overlay removal (`#close`, `.jw-ad-container`, `iframe[src*="ad.html"]`) to `LiveWebEmbedPlayerView.swift`.
- **Why**: StreamEx and VipLeague embeds using JW Player often stall on black screens when third-party ad networks fail or place transparent clickjack overlays over the video player. Calling the JW Player playback API directly forces instant HLS streaming without user interaction bottlenecks.

## 2026-08-13: StreamEx Network Feeds & Provider Matching Fix
- **Decision**: Expanded `StreamPluginProviderMatching` to include all StreamEx network web embeds (`delta`, `echo`, `golf`, `india`, `hotel`). Removed artificial filters that wrongly discarded StreamEx's `echo` and regional feeds.
- **Why**: StreamEx serves matches across several source codes on `embed.st`. The previous strict filter was mistakenly dropping StreamEx feeds (such as Vasco da Gama and Leagues Cup fixtures), causing "Stream Not Available" alerts on legitimate live matches.

## 2026-08-13: UI Scroll Performance & Loading Animation Optimization
- **Decision**: Added memoized `O(1)` dictionary lookup cache to `LiveScoreService.findMatch(home:away:)` to eliminate 30,000+ redundant fuzzy string regex scans per scroll frame. Virtualized match lists with `LazyVStack` in `DashboardMatchList.swift`. Removed heavy per-badge `@ObservedObject` subscriptions in `FlagSquircleBadge`. Upgraded `FootballLoadingView` to display-linked `TimelineView(.animation)` for continuous 60/120 FPS rendering.
- **Why**: Drastically improves iPad/iOS scrolling responsiveness, eliminates frame drops, and delivers a silky-smooth experience across 60+ live and upcoming fixtures.

## 2026-08-13: StreamEx Play/Pause Toggle Bug Fix (WebKit Script Refactor)
- **Decision**: Fixed the recurring play/pause toggle loop in `LiveWebEmbedPlayerView.swift`. Eliminated recurring click polling on player overlay containers (`.jw-display-icon-display`), replaced loop with an early-terminating one-time kick, and removed asynchronous programmatic unmuting that caused iOS WebKit audio policy suspensions.
- **Why**: StreamEx embeds JW Player in child iframes where parent frame polling re-clicked the video canvas every 3.5s, inadvertently sending PAUSE commands to active streams.

## 2026-08-13: Codebase Cleanliness, Mega-File Modularization & PocketBase Retirement
- **Decision**: Modularized the 3,666-line `SocialHubView.swift` mega-file by extracting isolated components into `Fotty/Features/Social/Components/` (`MatchChatView.swift`, `DirectChatView.swift`, `SocialCelebrationViews.swift`). Retired dead legacy `PocketBaseClient.swift` (16KB REST client) and cleaned up `SocialCloudStore.swift` and `FootballService.swift` `TeamBrandService` to operate as local-first stores backed by SwiftData, `UserProfileStore`, and reliable remote CDNs (ESPN & TheSportsDB). Regenerated project via XcodeGen and verified clean zero-error compilation.
- **Why**: Drastically improves codebase readability, build compile times, and eliminates dead networking code while preserving 100% feature capability.

## 2026-08-13: Interactive FPL Pitch Swapper & Lock Screen Media Controls
- **Decision**: Added interactive tap-to-swap substitutions in `FPLSquadPitchView` with dynamic formation calculation and projected point delta badges. Upgraded `FPLPriceAlertsView` with velocity progress barometers. Created `NowPlayingManager` to bind iOS Lock Screen and Control Center `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` controls to stream playback.
- **Why**: Drastically improves user agency when experimenting with FPL tactical lineups and provides seamless system-level media integration.

## 2026-08-13: Fortifying Core Pillars (FPL Snapshots, Scraper Resilience, Local User Storage)
- **Decision**: Added persistent disk caching to `FPLService` to eliminate deadline/pre-season lockout failures. Created `tools/stream_health_checker.py` to continuously validate catalog mirrors. Added `UserProfileStore` for local preferences & FPL Manager ID persistence and decoupled iOS from retired PocketBase backend. Implemented interactive 5-axis Radar Chart in FPL comparisons and web embed auto-failover in `LiveWebEmbedPlayerView`.
- **Why**: Eliminates the 4 primary fragility vectors identified across streaming, review mode gating, FPL API downtime, and retired cloud backends.

## 2026-08-12: Both surfaces — Worker Watch + Score808 host-frame on iOS
- **Decision**: getfotty.com Watch must always hit the Cloudflare playback Worker for `/api/live/streams` (default `FOTTY_DEFAULTS.playbackApiBase`); do not synthesize dead “Fotty 1–4” shells when the Worker is reachable. Feed list shows StreamEx/Score808 titles like iOS. iOS keeps Score808 Safari host-frame (`score808live.tv` parent → embed.st iframe) plus CDN allowlists.
- **Why**: Site was unusable (Aug 3 static deploy; Watch called same-origin HTML as JSON). App Score808 failures were WKWebView context/filters, not dead sources.
- **Deploy**: `tools/web-deploy-ftp.sh` (needs `FOTTY_FTP_PASSWORD`) + `tools/ios-deploy-device.sh`.

## 2026-08-09: Score808/StreamEx failures were app WKWebView filters, not the sources
- **Decision**: Treat JW `hls:networkError_manifestLoadError`, StreamEx random pause, and Watch Now “Looking for a playable stream…” as **Fotty app bugs**. Score808 and StreamEx play in Safari; do not blame or retire those sources for in-app breakage.
- **Why**: `LiveWebEmbedPlayerView` treated `cloudfront.net` (and similar media CDNs) as ads in JS `isNuisanceURL` and Swift `blockedHostFragments`, cancelling HLS manifests. Allowlist omitted `embed.st` / Score808 hosts. Aggressive autoplay re-clicked JW play/pause. Resolve piled headless extract / stub retries on top. Fix: keep media CDNs out of ad blocks; direct `webView.load` with correct Referer; soft autoplay after start; Watch Now returns hotel+delta web embeds quickly (no long extract hang).
- **Follow-up**: Device-verify Score808 plays, StreamEx stays playing, Watch Now opens in a few seconds; keep P2P out of the player source list.

## 2026-08-09: Score808 works — app must match Safari host context
- **Decision**: Keep synthesizing `hotel` from donor StreamEx ids when Nexus omits it. Prefer Score808 in the source list. For hotel playback, load a **score808live.tv host-frame** that iframes `embed.st` (Safari parity). Do not `loadHTMLString` the embed document body. Keep media CDNs out of WKWebView ad blocks.
- **Why**: Users watch full matches on Score808 in Safari. In-app `manifestLoadError` was Fotty (CDN ad-block + loading embed.st as top document), not a dead Score808 feed. Treating donor-id hotel as “fake” was wrong.
- **Supersedes**: “Do not invent Score808 from StreamEx ids” / defaulting away from Score808.

## 2026-08-03: PocketBase retired on web — open Watch without VPS
- **Decision**: Homelab PocketBase is out. Web defaults `NEXT_PUBLIC_ACCOUNTS_ENABLED` off; Watch is open to guests; login/signup CTAs and `/api/pocketbase/*` return paused/410; no pixel-invoice PocketBase/P2P defaults. Stay on FTP + playback Worker until a paid VPS is justified for same-origin HLS/unmute.
- **Why**: Auth backend is gone with the homelab; splitting a VPS only for unmute is deferred. Maximize companion site on current hosting.
- **Follow-up**: Choose a new auth provider later; optional full-site VPS if unmute/HLS parity is funded.

## 2026-08-03: Static `/api/matches` stays same-origin
- **Decision**: `NEXT_PUBLIC_FOTTY_API_BASE` only rewrites **playback** paths (`/api/live/*`, `/api/embed/*`, `/api/stream*`, `/api/status`, `/api/p2p/health`). Catalog JSON like `/api/matches` stays on getfotty.com.
- **Why**: Sending matches to the playback Worker returned 404 → Home showed “fresh refresh failed” despite a healthy static matches file.

## 2026-08-02: Watch in-page via direct embed.st iframe
- **Decision**: Watch plays StreamEx in-page with a direct `embed.st` iframe (`referrerPolicy=no-referrer`). No new tab. Unmute overlay only for same-origin proxied players.
- **Why**: Users rejected new-tab playback. CF Workers get stub embed HTML; Apache can fetch player HTML but **strmd HLS returns 403** to the host IP, so PHP unmute/HLS proxy cannot complete playback. Direct iframe from the browser works.
- **Follow-up**: Contabo (or other non-blocked VPS) for true same-origin HLS + unmute bridge.

## 2026-06-18: Web Event Failover Ignores Stale Iframe Callbacks
- **Decision**: Direct-event iframe load and error callbacks must identify the embed URL that emitted them, and the watch page must ignore callbacks from a feed that has already been replaced.
- **Why**: A failed feed could trigger selection of a backup, then emit a late `load` event. Because iframe `load` only means an HTML document loaded (including provider error pages), the stale callback marked the new feed as loaded and cancelled its timeout, so automatic failover appeared intermittent.
- **Implementation**:
  - Changed `DirectEventPlayer` load/error callbacks to include their embed URL.
  - Added a commit-time current-embed guard in the watch page so callbacks from replaced iframes cannot change the active feed's load state or retry path.
- **Verification**:
  - Ran the focused stream ranking/failover tests (4 passing).
  - Ran focused ESLint; only three existing React compiler warnings remain in `WatchPageClient`.
  - Ran TypeScript with `--noEmit` successfully.

## 2026-06-13: Web Direct P2P Should Follow The Native App Route
- **Decision**: `p2pRoute=direct` on Fotty Web should use a native-style public P2P manifest route backed by a short-lived signed `stream_token`, not the Next.js `/api/stream` segment wrapper.
- **Why**: The mobile app plays P2P streams reliably by handing AVPlayer/ExoPlayer the P2P proxy HLS URL directly, while desktop Chrome continued to buffer or stop even after the old web direct route skipped broker session reuse. Server and Mac-style probes showed the P2P proxy can return FOX Sports 2 manifests and range-capable `video/mp2t` segments; the remaining difference was the browser/Next.js HLS wrapper path.
- **Implementation**:
  - Added signed public stream-token verification to `fotty-p2p-proxy` for `/proxy/acestream/stream`, `/proxy/acestream/manifest.m3u8`, and `/ace/proxy`.
  - Added `web/src/app/api/stream/native/route.ts`, which validates Fotty paid watch access, issues a short-lived P2P stream token, and redirects HLS clients to `https://p2p.pixel-invoice.com/proxy/acestream/stream`.
  - Changed `p2pRoute=direct` / `native` / `edge` / `app` watch URLs to use the native route.
  - Tuned the web HLS.js P2P player toward native-player behavior: larger startup buffer, longer stall/decode tolerance, lower live-edge chasing, and no custom Fotty headers on the redirecting native route.
  - Kept the real P2P API password server-side; browser-visible manifests/segments use `stream_token` and do not include `api_password`.
- **Verification**:
  - Ran `python3 -m py_compile server/p2p_proxy_service.py`.
  - Ran `PYTHONPATH=server python3 -m unittest server.tests.test_p2p_proxy_service`.
  - Ran focused ESLint and TypeScript checks for the new web route/player/watch changes; ESLint only reports existing React compiler warnings.
  - Ran the local production web build successfully.
  - Deployed `fotty-p2p-proxy` and `fotty-web` to the homelab/public site.
  - Ran a sanitized production smoke from inside `fotty-web`: `/api/stream/native` returned 307 to the public P2P proxy, the manifest returned 200 with `stream_token` and no `api_password`, and the first FOX Sports 2 segment returned HTTP 206 `video/mp2t` with `Content-Range`.
- **Follow-up**:
  - Have a signed-in user test the same FOX Sports 2 URL in desktop Chrome with `p2pRoute=direct`.
  - If this holds, make the native direct route the default for P2P web playback and keep the broker path as fallback/diagnostics.
  - Add an automated Chrome smoke that follows `/api/stream/native` and asserts first-frame decode, not only manifest/segment bytes.

## 2026-06-13: Current Ace Engine Beats Latest For FOX Direct Playback
- **Decision**: Keep production on `vstavrinov/acestream-engine:3.1.75-4` for now and test a slimmer Fotty direct P2P watch route before touching the Ace engine image again.
- **Why**: A true host-network swap to `vstavrinov/acestream-engine:latest` reported engine `3.2.11`, but it did not produce reliable media for the channels Fotty needs most. FOX Sports 2 timed out on the direct playback URL, FOX Sports 1 produced only a tiny manifest and then timed out on the first segment, and ESPN timed out while reporting peers. After rollback, the current `3.1.75rc4` engine immediately produced FOX Sports 2 and FOX Sports 1 HLS manifests plus real TS segment bytes.
- **Implementation**:
  - Briefly stopped the old host-network Ace engine, ran the latest image on the real `6878` host port, tested priority CIDs, then rolled back to the old engine.
  - Cleared stale Fotty broker session keys after rollback so failed latest-engine playback URLs would not be reused.
  - Added `p2pRoute=direct` to the web watch page. In that mode Fotty uses the existing `/api/stream?id=<cid>` direct path immediately and skips broker warm-up/session reuse.
- **Verification**:
  - Confirmed production is back on `3.1.75rc4`.
  - Confirmed the P2P proxy direct endpoint returns a FOX Sports 2 manifest and range-capable `video/mp2t` segments through the old engine.
  - Ran focused TypeScript and ESLint checks for the watch page; ESLint only reports existing React compiler warnings.
  - Ran the local production web build and deployed `fotty-web`.
  - Confirmed a signed deployed-stack smoke call to `/api/stream?id=<FOX Sports 2 CID>` returns a manifest in about 6 seconds and the first segment returns HTTP 206 with `video/mp2t`.
- **Follow-up**:
  - Manually test the signed-in public watch URL with `p2pRoute=direct` in Chrome, Firefox, and Safari before making direct mode the default.
  - Do not expose the raw Ace engine port publicly. Keep public access behind Fotty auth and the web/P2P proxy.
  - Move hardcoded P2P secrets out of compose and rotate them.

## 2026-06-13: AceStream Engine Needs A Latest-Image Canary Before Any Production Swap
- **Decision**: Treat the current AceStream setup as a stale but known production path, then canary a newer engine image before replacing it. Do not blindly switch wrappers during World Cup traffic.
- **Why**: The live homelab engine is pinned to `vstavrinov/acestream-engine:3.1.75-4` and reports engine version `3.1.75rc4`. A sidecar smoke test of `vstavrinov/acestream-engine:latest` booted successfully and reported engine version `3.2.11`; `3.2.3-1` also booted and reported `3.2.3`. That means Fotty is not running the latest available engine image, but the latest image still needs real-CID testing before it touches the public path.
- **Implementation**:
  - Confirmed the live stack routes `fotty-p2p-proxy` directly to the Ace engine with `P2P_UPSTREAM_KIND=engine`.
  - Confirmed the live stack is not currently using the `mediaflow-proxy` service from `server/p2p-stack-updated.yml`.
  - Confirmed the newer Ace engine tags start in an isolated sidecar on an alternate local port without altering the running production container.
  - Confirmed the P2P proxy itself is healthy, Redis-backed, and serving a scraper catalog, but prewarming is disabled.
- **Follow-up**:
  - Canary `vstavrinov/acestream-engine:latest` or a pinned digest that reports `3.2.11` against real high-priority CIDs such as FOX Sports 2 before production rollout.
  - Keep rollback to `vstavrinov/acestream-engine:3.1.75-4` explicit in the compose notes.
  - Reconcile homelab compose drift between the live `/home/jelani/acestream/docker-compose.yml` and repo compose files.
  - Move the P2P API password out of compose into an environment file or secret and rotate it.
  - Evaluate `mediaflow-proxy` and `martinbjeldbak/acestream-http-proxy` as separate lab comparisons rather than direct replacements for the current upstream contract.

## 2026-06-13: ViniPlay Runs As A Private IPTV Lab
- **Decision**: Run ViniPlay as a private Tailscale-bound lab sidecar, not as a Fotty production dependency yet.
- **Why**: AceStream remains fragile for browser playback, but ViniPlay is an IPTV/player/proxy harness rather than a channel source. It can quickly test whether M3U/XC sources plus FFmpeg remuxing provide steadier Chrome, Safari, and mobile playback before Fotty commits to a native IPTV gateway.
- **Implementation**:
  - Started `ardovini/viniplay:latest` on the homelab with a persistent `/home/jelani/viniplay/data` volume and `restart: always`.
  - Bound the lab only to the homelab Tailscale address on port `8998` so it stays out of the public Fotty path.
  - Created a lab admin, loaded a public sports M3U source, loaded the current Fotty XMLTV guide, and processed both sources.
  - Switched the active stream profile from raw redirect to ViniPlay's FFmpeg MPEG-TS profile so the lab tests server-side media routing instead of plain browser redirects.
- **Verification**:
  - Confirmed ViniPlay served the app over the private Tailscale URL.
  - Confirmed source processing loaded 354 sports channels and 701 matched live-guide programs.
  - Confirmed a known-good FIFA+ channel produced HTTP 200 MPEG-TS through ViniPlay's FFmpeg `/stream` endpoint and delivered about 24 MB in a 15-second smoke pull.
  - Confirmed public free-playlist FOX entries are not reliable enough to be treated as World Cup coverage by themselves: one had broken segment range behavior and another timed out from the ViniPlay container.
  - Added the public Free-TV playlist as a second lab M3U; it processed 1,888 additional channels, but the focused sports probe showed most match-relevant channels were blocked, missing, refused, geo-limited, or stale. A few regional/specialty sports channels started, but Free-TV did not materially change the World Cup coverage answer.
- **Follow-up**:
  - Test with authorized M3U/XC sources before any Fotty integration.
  - If reliability is good, build a Fotty-owned IPTV gateway instead of copying ViniPlay code, because ViniPlay's current license is not suitable for a paid production Fotty dependency without permission.

## 2026-06-13: Browser WebRTC HLS Delivery Is A Flagged Ace Experiment
- **Decision**: Fotty Web can optionally wrap broker-served AceStream HLS with P2P Media Loader/WebRTC in the browser, but the path must remain default-off until real two-client swarm behavior is proven.
- **Why**: AceStream has repeatedly been the weakest link for desktop playback during World Cup preparation. A browser-side WebRTC HLS layer may reduce repeated segment pulls from Fotty's proxy once multiple viewers watch the same CID, but it cannot fix a dead Ace source, frozen broker playlist, or manifest/auth failure by itself.
- **Implementation**:
  - Added a `plain-hls` default and `p2pDelivery=webrtc` opt-in path for watch URLs.
  - Dynamically loads P2P Media Loader only when the experiment is enabled, then injects its Hls.js mixin around the existing Fotty player.
  - Uses a stable swarm id per Ace CID, `fotty-ace:<cid>`, so viewers on the same channel can discover the same segment swarm.
  - Falls back to normal Fotty HLS if the loader script, browser support, or Media Loader API is unavailable.
  - Exposes bounded DOM/debug markers for delivery mode, swarm id, and recent P2P events so production browser tests can verify whether the experiment actually engages.
  - Wired the player-level `Retry stream` button into the watch page's broker retry path so a failed media element forces a fresh broker session instead of replaying the same stale HLS session.
- **Verification**:
  - Ran focused ESLint and TypeScript checks; only the existing React compiler warnings in `VideoPlayer` remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Browser-smoked the public FOX Sports 2 HD watch URL with `p2pDelivery=webrtc`; the page loaded the Media Loader script, rendered the `P2P WebRTC` badge, initialized `webrtc-hls`, used the stable FOX Sports 2 swarm id, and recorded `onChunkDownloaded` events.
  - Earlier in the same smoke run, the video element reached a live playing state with decoded 1280x720 video while the Media Loader path was enabled.
  - After a FOX Sports 2 screenshot showed `Playback unavailable` with broker `manifest_403`, confirmed a fresh backend broker session became ready in 5 seconds, deployed the retry handoff patch, reloaded the public watch URL, and verified active 1280x720 playback with buffered video and WebRTC-HLS chunk downloads.
- **Follow-up**:
  - Prove or reject the experiment with two real desktop/mobile clients on the same watch URL at the same time and require `onPeerConnect` / `onChunkUploaded` before treating it as useful.
  - Do not ship public-tracker defaults for production; use a private tracker/signaling setup if the two-client test is promising.

## 2026-06-13: Web P2P Playback Recovers Stale Browser Sessions
- **Decision**: Fotty Web should treat P2P browser/player failures as recoverable while the broker is still serving manifests and segments, and should preserve media range headers through the Next.js segment wrapper.
- **Why**: FOX Sports 2 HD could show `Playback unavailable` even while the Match Center reported peers, speed, segments, and buffer. Server logs showed the broker serving manifests/segments, but the browser player was turning stale session manifests, video element errors, or HLS fatal events into terminal UI.
- **Implementation**:
  - Added bounded video-element recovery in `VideoPlayer` before showing the terminal playback overlay.
  - Added bounded watch-page broker session recycling when the P2P player reports a startup failure.
  - Forwarded browser `Range` requests through `/api/stream/segment` and preserved upstream `Content-Length`, `Content-Range`, `Accept-Ranges`, and exposed range headers for Chrome/HLS.js.
  - Disabled noisy production HLS debug logging.
- **Verification**:
  - Ran focused ESLint and TypeScript checks for the watch/player/segment route changes; only existing React compiler set-state-in-effect warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Confirmed public FOX Sports 2 watch route returns 200 and the public P2P catalog includes `FOX Sports 2 HD`.
  - Confirmed a signed public `/api/stream/segment` range request returns `video/mp2t`, `Content-Length`, `Content-Range`, `Accept-Ranges`, and exposed range headers.
  - Browser-smoked the FOX Sports 2 watch page: after reload it stayed out of the `Playback unavailable` overlay with the P2P broker session active; the Codex in-app browser still did not expose decoded dimensions, so final real-browser Chrome/Safari verification remains required.

## 2026-06-13: P2P Guide Proxy Must Restart Always
- **Decision**: The homelab `fotty-p2p-proxy` container and deploy script should use Docker `restart: always`, not `unless-stopped`.
- **Why**: The public TV Guide can render `0 shown / 0 mapped` when the proxy is down even if the web app and EPG file are healthy. On June 13, the proxy had exited with code 137 and stayed down, causing `scraper.pixel-invoice.com/matches` to return 502 and the web P2P channel API to return zero rows.
- **Implementation**:
  - Restarted the live `fotty-p2p-proxy` container.
  - Updated the running container restart policy to `always`.
  - Updated `tools/p2p-proxy-deploy-homelab.sh` and `server/p2p-stack-updated.yml` so future proxy deploys keep the stronger restart policy.
- **Verification**:
  - Confirmed public `https://scraper.pixel-invoice.com/matches` returned 188 channels after restart.
  - Confirmed public `https://fotty.pixel-invoice.com/api/p2p/channels` returned 125 filtered channels.
  - Confirmed `FOX Sports 1 HD` and `FOX Sports 2 HD` are available P2P channels and map to `FoxSports1.us@HD` / `FoxSports2.us@HD`.
  - Confirmed the guide API returned 79 requested rows, 25 mapped channels, and 23 schedule-backed channels; browser hydration showed `28 shown / 28 mapped`.

## 2026-06-13: World Cup Flags And Results Provider Ownership
- **Decision**: Fotty Web's World Cup surface should render country flags from an explicit tournament team map, while automatic score/result ingestion should be owned by football data providers rather than watch-path providers.
- **Why**: National-team fixtures looked unfinished when country badges fell back to initials. Separately, the web World Cup tab was consuming StreameX/Streamed/P2P schedule and watch sources, which are useful for playback paths but not authoritative for tournament results, tables, or team metadata.
- **Implementation**:
  - Added a flag map for all 48 World Cup group teams and a `worldCupTeamFlag()` helper.
  - Preserved World Cup flags when seeded fixtures are replaced by provider rows.
  - Updated the shared team badge renderer so flag emoji display as local badges instead of being treated as remote image IDs.
  - Surfaced flags in the World Cup hero matchup, fixture calendar rows, and group table rows.
- **Verification**:
  - Ran focused ESLint for `WorldCupView`, `TeamBadge`, and `world-cup.ts`.
  - Ran TypeScript checks successfully.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Smoked public `/world-cup`, `/world-cup?tab=groups`, and `/world-cup?tab=schedule`; all returned 200 and rendered country flags with the current seeded result rows.
- **Follow-up**:
  - Wire a dedicated web World Cup results API to the existing football-data/API-Football provider stack so scores and standings update automatically instead of relying on fallback result seeds.

## 2026-06-12: Admin-Issued One-Time QR Login
- **Decision**: Fotty Web admin can issue a 15-minute, single-use QR login link for a selected PocketBase account.
- **Why**: Match-day onboarding often happens through WhatsApp or in-person setup. Users should be able to scan a code and enter Fotty without typing a temporary password, while avoiding permanent QR/session leakage.
- **Implementation**:
  - Added server-side one-time QR login records in `.data/qr-login-links.json`, storing only token hashes.
  - Added `/api/admin/login-links` for admin link generation and `/api/auth/qr/redeem` for public one-time redemption.
  - Added signed `provider: "qr"` Fotty sessions that work with entitlement refresh and protected watch APIs without exposing the user's PocketBase password.
  - Added `/login/qr` to redeem links client-side and store the normal Fotty web auth session.
  - Added a selected-account admin panel that shows a QR image, copyable link, and expiry.
- **Verification**:
  - Ran focused ESLint; only pre-existing dashboard React hook warnings remain.
  - Ran local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Generated a production QR link for `smoke@fotty.app`, redeemed it once, confirmed Plus entitlement resolves, and confirmed a second redemption fails with "already used."

## 2026-06-11: Admin User List Handles Empty PocketBase Responses
- **Decision**: Fotty Web admin should show local grants when PocketBase user listing succeeds but returns zero users while local grants exist.
- **Why**: Production had local Plus grants for test/smoke accounts, but the admin dashboard still rendered "No users found" because the PocketBase request no longer threw. It returned a successful empty list, so the earlier error-only fallback never ran. Follow-up investigation found the deeper cause: `POCKETBASE_ADMIN_TOKEN` was an expired PocketBase admin JWT, so the `users` collection rule filtered the request down to zero rows even though the PocketBase DB had 22 users.
- **Implementation**:
  - `/api/admin/users` now loads local grants after a PocketBase list and switches to local source when PocketBase reports `0` users and local grants are present.
  - The admin dashboard displays the fallback warning and clamps pagination to at least one page.
  - Rotated the PocketBase admin credential on the homelab, stored fresh admin auth env in the deploy environment, and redeployed `fotty-web`.
  - Added `getPocketBaseAdminTokenForRequest()` so server routes can refresh the PocketBase admin JWT from `PB_ADMIN_EMAIL`/`PB_ADMIN_PASSWORD` instead of relying on a pasted short-lived token.
  - Added the required PocketBase `role: "user"` field to admin-created users so account creation no longer fails with `Missing required value.`
- **Verification**:
  - Ran focused ESLint for the touched admin files; only pre-existing React hook warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site.
  - Confirmed the live container returns `source: pocketbase`, `totalItems: 22`, `totalPages: 2`, and all expected PocketBase users from `/api/admin/users`.
  - Created and immediately deleted a temporary PocketBase user through the production `/api/admin/users` route to verify account creation end-to-end.

## 2026-06-11: Desktop Watch Path Errors Need Tokenized Playback Verification
- **Decision**: Treat `No verified watch path yet` reports as a playback/auth verification problem until the current browser bundle, watch-token handoff, manifest response, and actual video element state have all been checked.
- **Why**: Production stream prep was healthy, but a desktop tab could still show stale watch UI or a manifest `403` while the broker had peers and segments. Reloading onto the service-worker v17 shell restored the P2P HLS token handoff and changed BT Sport 2 from `Playback unavailable` to an active playing video.
- **Implementation**:
  - Preserved direct-event API errors through `useEventStreams` instead of replacing them with generic no-path copy.
  - Changed watch fallback headlines to distinguish session refresh, live access, broker/source failure, and true missing watch paths.
  - Bumped the service-worker shell to `fotty-shell-v17` and redeployed the public web container.
- **Verification**:
  - Confirmed public `sw.js` serves `fotty-shell-v17`.
  - Confirmed token-backed smoke access returns two UCI direct event streams and can create a BT Sport 2 P2P broker session.
  - Reloaded the public BT Sport 2 watch page in the browser and confirmed an active video element (`readyState=4`, `paused=false`, buffered, no media error).
  - Loaded the exact UCI Tour Auvergne URL and confirmed it renders a direct iframe plus `Try backup`/`Open feed`, two direct feeds, same-match P2P backups, and no console errors.

## 2026-06-11: Watch Failures Must Preserve Their Real Cause
- **Decision**: Fotty Web should not collapse broker, auth, access, network, and stale-client failures into the generic `No verified watch path yet` copy.
- **Why**: Desktop users were repeatedly reporting the same message even when production APIs were healthy. That made different failure classes indistinguishable and encouraged repeated one-off fixes instead of a reliable launch workflow.
- **Implementation**:
  - Changed the web API client to return specific broker failure messages for expired sign-in, missing live access, rate limit, broker failure, missing session, and device network failure.
  - Changed the P2P watch hook to surface the returned broker message instead of replacing it with generic no-path copy.
  - Changed direct-event unavailable state to show the actual stream lookup error.
  - Bumped the service-worker shell cache to `fotty-shell-v16` and made the PWA registration update/reload once when a new worker takes control, reducing stale desktop tabs after deploys.
- **Verification**:
  - Ran focused ESLint on `api.ts`, `useP2PBrokerSession.ts`, `WatchPlayers.tsx`, and `PWARegister.tsx`; no errors, with the existing React set-state-in-effect warning still present in the P2P hook.
  - Ran `npm run build:standalone`.
  - Deployed `fotty-web` to the homelab/public site.
  - Confirmed public `sw.js` serves `fotty-shell-v16`.
  - Confirmed the UCI direct event lookup returns two streams.
  - Confirmed public BT Sport 2 P2P broker session returns ready with playable segments.
  - Confirmed the browser-rendered BT Sport 2 watch page has an active video (`readyState=4`), peers/segments visible, and no console errors.

## 2026-06-11: Cloudflare Tunnel Outage Was Homelab Wi-Fi Loss
- **Decision**: Treat the Fotty homelab Wi-Fi link as a launch risk until the tunnel host is moved to wired networking, a second Cloudflare Tunnel connector, or a hosted deployment target.
- **Why**: Hours before World Cup traffic, all public hostnames (`fotty`, `scraper`, `p2p`, and `fotty-api`) returned Cloudflare 1033/HTTP 530. Local Fotty containers were healthy once SSH was reachable, but NetworkManager logs showed `wlp3s0` lost the AP at 12:00:15 AST, failed with `ssid-not-found` at 12:00:30, and reconnected at 12:13:31. `cloudflared` recovered at 12:13:56 after the Wi-Fi returned.
- **Implementation**:
  - Verified local services on the host: `fotty-web` on `127.0.0.1:3010`, `fotty-p2p-proxy` on `127.0.0.1:8006`, and the scraper route all returned locally.
  - Confirmed the public tunnel recovered and all key public routes returned HTTP 200.
  - Attempted to disable Wi-Fi power saving, but the SSH session lacks non-interactive sudo; the host still reports `Power save: on`.
- **Verification**:
  - Confirmed public `https://fotty.pixel-invoice.com/`, `/world-cup`, `/guide`, and `https://scraper.pixel-invoice.com/matches` return HTTP 200.
  - Confirmed `cloudflared` has four registered edge connections after recovery.
  - Action for operator: on the Linux host, run `sudo iw dev wlp3s0 set power_save off` and `sudo nmcli connection modify "Digicel_5G_WiFi_Ep9r" 802-11-wireless.powersave 2`, or move the host to Ethernet.

## 2026-06-11: Direct Event Playback Needs Desktop Escape Hatches
- **Decision**: Fotty Web direct event watch pages should expose desktop-safe fallback controls on top of the event player and provide a cache-refresh recovery path when the watch route error boundary appears.
- **Why**: The UCI Tour Auvergne event returned valid direct StreameX embeds and same-match P2P alternates, but desktop users could still see a black/failed provider frame or `Stream page failed to load` while another device played the same event. The parent Fotty page cannot reliably inspect cross-origin embed playback state after the iframe loads.
- **Implementation**:
  - Added player-level `Try backup` and `Open feed` controls for direct event iframes, so desktop users can switch provider variants or open the provider as a top-level page when iframe playback stalls.
  - Added a watch error-boundary `Refresh app` action that clears Fotty shell caches, requests service-worker updates, and reloads the route.
  - Kept the existing match hub backup list and same-match P2P alternates as secondary recovery paths.
- **Verification**:
  - Confirmed the exact UCI event stream API returns two direct event variants for a paid smoke account.
  - Confirmed the signed-in watch page renders the event iframe, backup feed, and same-match P2P alternates in the in-app browser.
  - Ran focused ESLint with no errors; the pre-existing `react-hooks/set-state-in-effect` warning in `WatchPageClient` remains.
  - Ran `npm run build:standalone` successfully.
  - Deployed `fotty-web` successfully after the tunnel recovered.
  - Confirmed the public UCI event stream API returns two direct event variants after deploy.

## 2026-06-11: Desktop Web Playback Must Not Use Stale Service-Worker Chunks
- **Decision**: Fotty Web's service worker should not cache Next.js `/_next/` assets or RSC payloads, and desktop media-session integration must be optional so browser API differences cannot crash the watch route.
- **Why**: Desktop users could see `No verified watch path yet` or the `/watch` error boundary (`Stream page failed to load`) while mobile playback worked. The P2P broker and stream APIs were healthy, so the likely desktop failure modes were stale service-worker-held client chunks and browser-specific `MediaMetadata` support.
- **Implementation**:
  - Bumped `web/public/sw.js` to `fotty-shell-v15`.
  - Excluded `/_next/` assets and `_rsc` payloads from service-worker caching, leaving navigations network-first and only caching the small static shell asset set.
  - Wrapped `VideoPlayer` media-session metadata/action setup in feature checks and a `try/catch`.
  - Changed P2P watch unavailable copy to show the broker warm-up/failure message when available instead of hiding it behind generic copy.
- **Verification**:
  - Ran focused ESLint for `VideoPlayer` and `WatchPageClient`; no errors, with pre-existing React set-state-in-effect warnings still present.
  - Ran `npm run build:standalone`.
  - Deployed `fotty-web` to production.
  - Confirmed public `sw.js` serves `fotty-shell-v15` and excludes `/_next/`/`_rsc`.
  - Confirmed public watch route returns HTTP 200.
  - Confirmed paid smoke account can issue a watch token, load a P2P HLS manifest, and fetch a video segment through `/api/stream/segment`.

## 2026-06-11: Production Watch Test Account Grant
- **Decision**: The production web image should include a local Plus grant for `test@test.com` alongside the existing `smoke@fotty.app` playback smoke account until PocketBase/admin entitlement persistence is fully configured.
- **Why**: Manual watch testing was reaching the client gate with `Live access required` even after the Guide recovered, because the account session could exist while the server-side watch-access resolver had no paid entitlement to verify for that email.
- **Implementation**:
  - Added `local:test@test.com` with `entitlement: "plus"` to the ignored deploy seed `web/.data/admin-grants.json`.
  - Redeployed `fotty-web` so the running container includes the grant.
- **Verification**:
  - Confirmed the running `fotty-web` container has both `smoke@fotty.app` and `test@test.com` Plus grants.
  - Confirmed the public P2P channel feed still returns live channels after redeploy.

## 2026-06-11: TV Guide Requires Live P2P Proxy, Not Just Fresh EPG
- **Decision**: Fotty Web's `/api/p2p/channels` route should be dynamic and bypass Next fetch caching, while the homelab `fotty-p2p-proxy` must remain running in front of the scraper and EPG status endpoints.
- **Why**: The public TV Guide can show `0 shown` and `0 mapped` even when the EPG file is fresh if `fotty-p2p-proxy` is down. On June 11, the scraper was still auto-refreshing channels, but the proxy container had exited with code 137 six days earlier and Cloudflare was returning `502` for `scraper.pixel-invoice.com` and `p2p.pixel-invoice.com`.
- **Implementation**:
  - Restarted `fotty-p2p-proxy` on the homelab so `/matches` and `/epg/status` were reachable through the public tunnel again.
  - Changed `web/src/app/api/p2p/channels/route.ts` to `dynamic = "force-dynamic"`, `revalidate = 0`, and `cache: "no-store"` so an empty P2P response is not held by the web layer.
  - Updated `TVGuideView` to track channel loading separately from EPG mapping so the Guide shows an updating state while listings are being matched instead of briefly showing the empty-state copy.
  - Deployed `fotty-web` with `./tools/web-deploy-homelab.sh` after the focused route change.
- **Verification**:
  - Confirmed public `https://scraper.pixel-invoice.com/matches` recovered with live channel rows.
  - Confirmed public `https://fotty.pixel-invoice.com/api/p2p/channels` returned over 100 playable channels after deploy.
  - Confirmed public `https://fotty.pixel-invoice.com/api/epg/guide` maps representative channels such as Sky Sports Football, Sky Sports Main Event, ESPN, and Tennis Channel HD with exact guide rows.
  - Verified the deployed public Guide renders `25 shown`, `25 mapped`, and no empty-state message after reload.

## 2026-06-11: World Cup Hub Public Update
- **Decision**: Fotty Web's `/world-cup` hub should use URL-backed tabs, FIFA-football-only World Cup filtering, and live World Cup headline cards before public match-day traffic.
- **Why**: The first World Cup fixture traffic exposed three launch issues: unrelated "World Cup" sports such as darts could leak into the hub, client-only tabs were too fragile in Safari, and the Stories tab was showing product-planning copy instead of real football stories.
- **Implementation**:
  - Tightened `isWorldCupMatch` to require football/FIFA/soccer context and reject non-FIFA sports such as darts.
  - Changed the World Cup tabs to real route links: `/world-cup`, `/world-cup?tab=schedule`, `/world-cup?tab=groups`, `/world-cup?tab=stories`, and `/world-cup?tab=watch`.
  - Filtered the initial `/world-cup` payload to provider-confirmed World Cup rows instead of serializing the full all-sports feed.
  - Replaced static Stories cards with live `/api/football/headlines` cards for current FIFA World Cup football stories.
  - Deployed `fotty-web` to the homelab/public site with `./tools/web-deploy-homelab.sh`.
- **Verification**:
  - Ran focused ESLint for `WorldCupView`, `/world-cup/page`, and `world-cup.ts`.
  - Ran `npm run build:standalone` locally and remote Docker `next build` through the deploy script.
  - Verified `https://fotty.pixel-invoice.com/world-cup` and all tab URLs return `200` with the expected section content.
  - Verified the public World Cup route and headline API return `NO_DARTS`.

## 2026-06-11: World Cup Hub Uses Published Fixture Seeds
- **Decision**: Fotty Web's `/world-cup` hub should load published 2026 FIFA World Cup group fixtures and groups from a deterministic seed list, then let provider feed matches replace seeded rows when real watch coverage appears.
- **Why**: The fixture draw is now public, but direct stream providers may not tag or expose every match yet. Users need trustworthy schedule, reminder, group, and guide paths immediately without Fotty pretending that unavailable broadcasts are playable.
- **Implementation**:
  - Added World Cup group/team data and opening fixture seeds to `web/src/lib/world-cup.ts`.
  - Converted fixture seeds into normal `ScrapedMatch` rows with `coverage: "unavailable"` so reminders work while watch buttons stay bounded by the existing broadcast window.
  - Merged seeded fixtures with provider World Cup matches by normalized team names and kickoff window to avoid duplicate rows once live providers catch up.
  - Replaced World Cup group placeholders with the actual group draw in `WorldCupView`.
- **Verification**:
  - Ran focused ESLint for `src/lib/world-cup.ts`, `src/components/WorldCupView.tsx`, and `src/app/world-cup/page.tsx`.
  - Ran `npm run build` successfully in `web`.

## 2026-06-03: Homelab EPG Heap Raised For Daily Refresh
- **Decision**: The homelab EPG cron remains the owner of Fotty TV guide refreshes, but the iptv-org Docker grabber now needs an 8GB Node heap.
- **Why**: The June 2 and June 3 scheduled jobs fired correctly but failed while saving the focused XMLTV output with `JavaScript heap out of memory`, leaving the public guide on the last successful June 1 file.
- **Implementation**:
  - Set `FOTTY_EPG_NODE_HEAP_MB=8192` in `/home/jelani/acestream/server/epg/epg.env` on the homelab.
  - Updated `server/epg/epg.env.example` so operators do not regress to the old 4096 MB value.
  - Added scheduled housekeeping so the refresh keeps a bounded number of logs and prunes old temp/backup files.
  - Set the homelab retention knobs to `FOTTY_EPG_LOG_KEEP=10`, `FOTTY_EPG_BACKUP_RETENTION_DAYS=7`, and `FOTTY_EPG_TEMP_RETENTION_DAYS=1`.
- **Verification**:
  - Confirmed crontab still has `0 4 * * * /home/jelani/acestream/server/epg/run_scheduled_refresh.sh # fotty-epg-refresh`.
  - Ran the scheduled refresh entrypoint manually; it completed in `00h 08m 28s`.
  - Confirmed `/data/epg/guide.xml` is dated `20260603`, `cached_body_bytes=3107706`, and `/epg/status` reports `ok=true`.
  - Confirmed the server has no EPG temp/backup leftovers, retains 10 refresh logs, and `/home/jelani/acestream` is at 13% disk usage.

## 2026-06-02: Shared Public Fallback States
- **Decision**: Fotty Web public pages should use shared fallback components for loading, empty, updating, signed-out, no verified stream, World Cup preparation, and data refresh states.
- **Why**: Paid-user and World Cup readiness requires every route to feel intentional even when live feeds, EPG, tables, or watch paths are unavailable. Blank panels, raw provider errors, and disappearing sections undermine trust.
- **Implementation**:
  - Added reusable fallback components and a bounded loading-timeout hook.
  - Applied product-quality states to Home, Live Board, Watch, TV Guide, Tables, World Cup Hub, and shared fixture lists.
  - Sanitized web auth/watch/provider failures so raw backend or broker errors are logged internally but not used as primary public copy.
  - Added `docs/audit/Fotty-Web-Fallback-State-Audit-2026-06-02.md`.
- **Verification**:
  - Ran `npm run build` successfully.
  - Smoked local production routes on port `3020`: `/`, `/swarm`, `/guide`, `/tables`, `/world-cup`, `/help`, `/welcome`, `/login`, `/settings`, and `/watch/test-source`.
  - Deployed `fotty-web` to the homelab and smoked the same public routes on `https://fotty.pixel-invoice.com`.

## 2026-06-02: Public Copy Must Sound Production-Ready
- **Decision**: Public Fotty Web copy should avoid prototype, MVP, concept, demo, experimental, and vague coming-soon language.
- **Why**: Fotty is being positioned for paid users and World Cup match-day traffic. Public surfaces need to sound calm, useful, and trustworthy even when data is updating or watch paths require sign-in.
- **Implementation**:
  - Updated Home hero badge, subtitle, and CTAs to `Fotty Match Hub`, `Open Live Board`, and `View World Cup Hub`.
  - Replaced guide loading, empty fixture, unavailable content, watch failure, and stream availability copy with intentional update/fallback language.
  - Removed the Settings link to internal signal tooling and renamed protected signal-console copy away from MVP wording.
  - Renamed lower-confidence stream-group internals away from `experimental`.
- **Verification**:
  - Scanned `web/src` for public prototype-style phrases; remaining hits are literal protected route paths such as `/mvp` and `/demo`.
  - Ran `npm run build` successfully.

## 2026-06-02: Web Production Trust And World Cup Readiness Pass
- **Decision**: Public Fotty Web pages should no longer present prototype language or invented fixture placeholders, and World Cup surfaces should show intentional updating states until official feed data is confirmed.
- **Why**: Paid users need trust that Home, Live Board, TV Guide, Tables, Watch, and World Cup Hub are reading the same match-day truth. Placeholder names such as `Home v Away`, MVP-style labels, and terse guide gaps make the service feel unfinished.
- **Implementation**:
  - Added a shared fixture normalization layer that treats provider placeholders as updating data and parses trustworthy fixture titles into team labels.
  - Normalized `/api/matches` output before public pages consume it.
  - Removed server-formatted kickoff text from match subtitles so pages format canonical `startsAt` timestamps in the viewer browser timezone.
  - Replaced public prototype copy and improved Home, TV Guide, Watch access, and World Cup fallback states.
  - Documented the route-by-route launch audit in `docs/audit/Fotty-Web-Production-Audit-2026-06-02.md`.
- **Verification**:
  - Ran `npm run build` successfully.
  - Started a fresh production server on port `3020` and confirmed `/`, `/swarm`, `/guide`, `/tables`, `/watch/test`, `/world-cup`, `/login`, and `/settings` all returned HTTP `200`.
  - `npm run lint` remains blocked by a pre-existing `any` in `web/e2e/prod-playback.spec.ts`.

## 2026-06-01: Direct Event Playback Must Use Real Provider Streams Only
- **Decision**: Direct event watch links should use unique event ids for the route, while P2P channel watch links continue to use AceStream CIDs. The web stream lookup should not fabricate a legacy embed when provider APIs return no playable variants unless an explicit fallback flag is enabled.
- **Why**: Multiple direct fixtures can share the same provider coverage CID, so routing event pages by CID makes playback state and fallback matching ambiguous. Fabricated embeds also made the UI report "feeds" and "stream ready" while the browser was handed a dead HLS manifest.
- **Implementation**:
  - Updated shared client and server watch-link builders to route event playback by `match.id`/`eventSource.id` before falling back to `cid`.
  - Gated the legacy `embedsports` direct-stream fallback behind `FOTTY_ENABLE_LEGACY_EMBED_FALLBACK=true`.
- **Verification**:
  - Ran focused ESLint for the changed watch-link and stream lookup files.
  - Ran `./tools/web-build-local.sh`.
  - Deployed `fotty-web` to the homelab and confirmed the public web container and P2P stack are up.

## 2026-06-01: Immediate P2P Broker Session Return
- **Decision**: Fotty Web should return a P2P broker session to the browser immediately, then let the watch page poll that session until it is ready or explicitly failed.
- **Why**: Cold AceStream startup can take longer than the first web timeout. Waiting inside `/api/stream/session` left the browser without a session id to poll, so the UI could mark a source unavailable while the homelab broker was still warming successfully.
- **Implementation**:
  - Changed `web/src/app/api/stream/session/route.ts` to call `createBrokerSession` directly instead of `createAndWarmBrokerSession`.
  - Extended the watch-page warmup window and allowed a previously failed UI state to recover when session polling later reports ready segments, a ready manifest, or active status.
- **Verification**:
  - Created a public broker session for the reported SkySP PL CID; it became ready with peers and validated segments after cold startup.
  - Ran focused ESLint for the changed API/watch files; only existing React hook warnings remain.
  - Ran `./tools/web-build-local.sh`.

## 2026-06-01: Server-Owned EPG Refresh Reliability
- **Decision**: The Fotty P2P guide refresh should run from the homelab cron job, with the EPG generator given an explicit larger Node heap.
- **Why**: The guide must refresh even when Codex usage is unavailable. The scheduled job existed, but the iptv-org generator was failing with `JavaScript heap out of memory`, leaving the public guide stuck on an old `guide.xml`.
- **Implementation**:
  - Updated `server/epg/refresh_epg.sh` so native and Docker EPG grabs use `NODE_OPTIONS=--max-old-space-size=${FOTTY_EPG_NODE_HEAP_MB:-4096}`.
  - Documented `FOTTY_EPG_NODE_HEAP_MB` in `server/epg/epg.env.example`.
  - Applied the script to the homelab and set `FOTTY_EPG_NODE_HEAP_MB=4096` in the server `epg.env`.
- **Verification**:
  - Confirmed the homelab crontab has `0 4 * * * /home/jelani/acestream/server/epg/run_scheduled_refresh.sh # fotty-epg-refresh`.
  - Ran the scheduled refresh manually on the server; it completed and published a fresh `guide.xml` dated `20260601`.
  - Confirmed public `/epg/status` reads `/data/epg/guide.xml` with `cached_body_bytes=3080550` and preview date `20260601`.

## 2026-05-31: Fotty 2.0 Live Board Visual Alignment
- **Decision**: The web `/swarm` live board should use the same premium match-day language as the redesigned home page, while keeping playback behavior unchanged.
- **Why**: A premium home page followed by an older live board makes the product feel inconsistent. The live board is a core paid-user surface, so it needs clearer hierarchy, stronger trust signals, and less intrusive install messaging.
- **Implementation**:
  - Updated the live board command strip, featured match panel, compact P2P source panel, and backup guide rows with cinematic dark styling and clearer source/status hierarchy.
  - Kept live board league selection all-first instead of quietly defaulting back to Premier League.
  - Limited the PWA install banner to help/onboarding/settings pages so it does not cover core match discovery screens.
- **Verification**:
  - Ran focused ESLint for `SwarmView` and `AppChrome`.
  - Ran `./tools/web-build-local.sh`.
  - Captured local Playwright screenshots for mobile and desktop `/swarm` match and P2P source views.

## 2026-05-24: EPG-Backed P2P Match Recovery On Web Watch Pages
- **Decision**: Event watch pages should restore same-match P2P options by matching P2P channels against verified EPG now/next listings, not only channel names.
- **Why**: Direct event embeds can fail even when the matching P2P channel is available. Channel labels like `SkySP PL` do not contain team names, so title-only matching missed the useful P2P fallback that previously made the watch page resilient.
- **Implementation**:
  - The watch page now fetches verified P2P EPG guide rows alongside the P2P catalog and scores channels using current programme/team/title matches.
  - P2P alternatives are shown above direct backup feeds so users can reach the broker player quickly when provider embeds fail.
  - Direct feed copy now says provider playback is still estimated and may require another backup or P2P route.
- **Verification**:
  - Ran focused ESLint for the watch page and stream hub files; only existing React set-state-in-effect warnings remain.
  - Ran `./tools/web-build-local.sh`.
  - Deployed to homelab and ran public smoke against `https://fotty.pixel-invoice.com`.

## 2026-05-23: World Cup Hub As A First-Class Web Surface
- **Decision**: Fotty Web should have a dedicated `/world-cup` hub and primary navigation entry ahead of the 2026 FIFA World Cup.
- **Why**: The tournament is large enough to become a daily habit loop: users need live matches, next kickoffs, reminders, stories, groups, guide links, and watch paths without hunting through general football filters.
- **Implementation**:
  - Added `web/src/app/world-cup/page.tsx`, `web/src/components/WorldCupView.tsx`, and `web/src/lib/world-cup.ts`.
  - Promoted World Cup into the primary nav and moved Teams under More to keep the mobile tab bar compact.
  - Seeded tournament milestones, host-region context, story cards, groups placeholder cards, and a watch-readiness checklist.
  - Reused the Fotty match feed, reminder buttons, watch-link builder, and pull-to-refresh so real World Cup fixtures auto-promote when the feed includes them.
  - Added `/world-cup` to web smoke coverage.
- **Verification**:
  - Ran focused ESLint for the new World Cup files and nav changes.
  - Ran `./tools/web-build-local.sh`.
  - Deployed to homelab and ran public smoke against `https://fotty.pixel-invoice.com`, including `/world-cup`.

## 2026-05-20: Deterministic Web Timezone For Hydration
- **Decision**: Fotty Web should render match time labels with an explicit `America/Port_of_Spain` timezone instead of relying on server or browser local timezone.
- **Why**: Desktop browsers in different timezones could hydrate different match-time text from the server-rendered HTML, producing React hydration error #418 and making the public site feel broken on some PCs.
- **Implementation**:
  - Added shared Fotty locale/timezone constants in `web/src/lib/live.ts`.
  - Updated match/feed/server labels and key stream-guide timestamps to use those constants.
  - Set `sw.js` to `no-store` and bumped the service-worker shell cache so public deploys update reliably.

## 2026-05-20: Web Event Embed Switching Safety
- **Decision**: Fotty Web event playback should keep provider embeds in their original provider origin for now, while sandboxing the iframe and forcing a full iframe reload when users switch feeds.
- **Why**: A Fotty-hosted embed wrapper reduced popup risk but changed the provider environment enough to stop playback. The Mac app still has stronger native extraction; web should first preserve playback and make backup switching reliable.
- **Implementation**:
  - Removed the Fotty-hosted embed wrapper from the active event player path.
  - Kept provider embeds sandboxed without popup permission.
  - Added a selected-stream key to the event iframe so tapping Backup Stream 1/2/etc. remounts the iframe instead of appearing to do nothing.

## 2026-05-19: P2P Web Stream Visibility and 416 Probe Fallback
- **Decision**: Web P2P channel lists should preserve every distinct CID, even when multiple feeds share the same channel display name.
- **Why**: Collapsing by channel title hid alternate P2P streams that users need when one feed is cold, unstable, or region-specific.
- **Implementation**:
  - Changed `/api/p2p/channels` dedupe to only remove exact duplicate CIDs.
  - Added a broker manifest probe fallback for segment servers that reject range probes with HTTP 416, retrying once without `Range` before marking the manifest unavailable.
  - Hardened the P2P proxy scraper cache so a pinned-only internal refresh cannot overwrite a larger healthy Redis channel catalog from the standalone scraper.

## 2026-05-15: Web Monetization Foundation
- **Decision**: Fotty Web monetization should start with identity, entitlements, sponsor placements, and soft premium convenience rather than hard-blocking match discovery.
- **Why**: The MVP needs a revenue path without damaging the match-first experience or delaying playback.
- **Implementation**:
  - Added a local entitlement model for Free, Fotty Plus, Match-Day Supporter, and Fotty Collab.
  - Added `/subscribe` with checkout URL support and a local MVP activation fallback.
  - Added sponsored slots on Home, P2P sources, and Watch surfaces that disappear for paid access.
  - Added Settings and top-bar access cues, plus login account/access copy.
  - Soft-gated the P2P "Verified" convenience filter behind Plus while keeping browsing available.

## 2026-05-15: Productized P2P Guide Controls
- **Decision**: The P2P backup page should expose guide-aware filters and trust signals before users open a source.
- **Why**: The page needs to feel like a viable product surface, not a raw list of streams. Users should be able to quickly choose between all sources, channels with current guide data, mapped guide channels, and playback-verified sources.
- **Implementation**:
  - Added All sources, On now, TV guide, and Verified controls to the P2P source page.
  - Marked guide-backed rows as "Verified guide" and non-mapped rows as "Channel-only backup."
  - Scoped featured/recommended rows to the active P2P guide filter so the page does not contradict the selected view.

## 2026-05-14: Verified P2P EPG Mapping
- **Decision**: Fotty Web must only show P2P TV guide data from verified channel identity mappings, not fuzzy channel-name matching.
- **Why**: Fuzzy matching made unrelated channels share listings, including Sky Sports Cricket showing football programming. A wrong guide is worse than no guide.
- **Implementation**:
  - Added `server/epg/p2p_epg_map.json` as the explicit Fotty P2P channel to XMLTV ID map.
  - Updated `/api/epg/guide` to return guide data only for `confidence=verified` mappings.
  - Updated the EPG refresh filter to build a focused channel list from verified XMLTV IDs.
  - Refreshed `server/epg/guide.xml` with separate Sky Sports Cricket, Sky Sports Football, Sky Sports Arena, ESPN/ESPN2, Poland, Germany, and Russia channel identities.

## 2026-05-14: Web Notifications and PocketBase MVP Schema
- **Decision**: Add browser reminder notifications for saved matches and make the required PocketBase web write collections explicit.
- **Why**: Team tracking needed a concrete reminder payoff for the MVP, while PocketBase setup needed exact collection targets instead of vague follow-up work.
- **Implementation**:
  - Added an in-browser reminder notifier that fires saved match reminders while Fotty is open.
  - Added notification permission controls to the Team Alerts page.
  - Added PocketBase write-target visibility to MVP Signals.
  - Documented the `team_follows`, `match_reminders`, `partner_inquiries`, and `support_pledges` web schema in `docs/PocketBase-Web-MVP-Schema.md`.

## 2026-05-14: Web PocketBase Sync Bridge
- **Decision**: Web MVP writes should attempt real PocketBase sync when the browser has a PocketBase-backed session, while preserving local-first behavior for test sessions.
- **Why**: iOS already uses PocketBase, and web should join that backend instead of remaining a purely local prototype.
- **Implementation**:
  - Added `/api/pocketbase/auth` for PocketBase user auth via `users/auth-with-password`.
  - Extended web auth sessions with optional PocketBase token/userID/provider fields.
  - Added `/api/pocketbase/sync` to sync team follows, match reminders, Collab inquiries, and support pledges to PocketBase collections.
  - Updated local storage helpers to write locally and then attempt background PocketBase sync.
  - Added smoke coverage for PocketBase auth/sync route behavior without a session.

## 2026-05-14: Web MVP Completion Pass
- **Decision**: Treat the web MVP as complete for local validation once the core product loops are functional and externally-blocked production switches are explicit.
- **Why**: Fotty needs a usable MVP now while real auth, payment checkout, browser push, and PocketBase write-sync remain separate integration tasks.
- **Implementation**:
  - Hardened watch-page direct stream loading with bounded lookup failure states and clearer unavailable-source actions.
  - Improved search scoring so exact team/title fixture matches rank above broad channel text.
  - Moved Collab inquiries and support pledges into typed shared storage helpers, ready to map to PocketBase records.
  - Added production-switch visibility to `/mvp` for PocketBase sync, payment links, real auth, and browser push.
  - Re-ran lint, production build, standalone prep, smoke tests, and browser checks for search/watch.

## 2026-05-14: Web MVP Product Loops
- **Decision**: The web MVP should expose the core loops directly: tracked-team personalization, Collab inquiries, support intent, and local product signals.
- **Why**: Fotty’s MVP needs to feel viable as a product, not only a match list. Users should see value from tracking teams, and builders should see whether Collab/support loops are being exercised.
- **Implementation**:
  - Added a Home “For Your Teams” section that appears when teams are tracked and surfaces matching fixtures with reminder actions.
  - Added `/mvp` as a local MVP Signals console for tracked teams, Collab inquiries, support pledges, and recent local events.
  - Linked MVP Signals from Settings and added `/mvp` smoke coverage.
  - Verified the loop by tracking a team, saving a Collab inquiry, and confirming both appear in MVP Signals.

## 2026-05-14: Collab as MVP Product Pillar
- **Decision**: Fotty Collab should be a first-class web MVP surface, not only a support-page option.
- **Why**: The MVP needs a viable product path beyond individual tips: venues, fan communities, sponsors, and clubs can use Fotty as a practical match-day hub.
- **Implementation**:
  - Added `/collab` with Watch Party Kit, Community Hub, Sponsor Placement, and Local Club Pilot package cards.
  - Added a collab inquiry workflow that captures organization, contact, region, audience size, match focus, and use case, then stores the inquiry locally.
  - Added `collab_inquiry_saved` analytics and smoke coverage for `/collab`.
  - Linked Collab from Home, Support, Settings, and the desktop top bar so it behaves like an MVP pillar.

## 2026-05-14: Functional Web Support Flow
- **Decision**: The web Support page should work as an interactive support flow before payment infrastructure is fully configured.
- **Why**: Static “Register interest” cards did not feel usable enough for monetization testing, and Fotty needs to validate support intent while external checkout links are still optional.
- **Implementation**:
  - Replaced passive support links with selectable support paths and a checkout panel.
  - Added monthly/one-time amount selection, custom amount, contact, and note fields.
  - Saved local pledges/inquiries to browser storage when payment links are absent, while keeping external payment URL support through environment variables.
  - Added local `support_pledge_saved` analytics and updated smoke coverage for the functional support funnel.

## 2026-05-14: Web PocketBase Team Badges
- **Decision**: The web `/api/matches` route should enrich fixture teams with `sports_teams.badge_url` from PocketBase before falling back to schedule-provided badges or initials.
- **Why**: The web match cards should share the same metadata source of truth as iOS instead of relying only on streamed schedule badge tokens.
- **Implementation**:
  - Added server-side PocketBase `sports_teams` badge fetching in `web/src/app/api/matches/route.ts`.
  - Normalized team names and short names into a lookup map, including common diacritics, so fixtures can resolve badges before rendering.
  - Added a smoke check that `/api/matches` includes at least one PocketBase-backed team badge URL.

## 2026-05-14: Web Team Alerts & Interest Routing
- **Decision**: Web should add local team tracking before full push/account notification infrastructure, and support registration interest should route into contextual feedback rather than a generic form.
- **Why**: Users need an obvious way to tell Fotty which teams matter now, while monetization links need to capture intent cleanly before payments and entitlements are fully wired.
- **Implementation**:
  - Added local tracked-team storage, a `/teams` Team Alerts page, settings entry, Home quick link, and featured-match Track buttons.
  - Added `track_team_click` local analytics for follow/unfollow actions.
  - Routed Support fallback CTAs to `/feedback?intent=...` and added Supporter interest/Partnership feedback categories with registration-interest context.
  - Extended the web smoke script to cover `/teams` and the support interest paths.

## 2026-05-14: Web Startup Load Reduction for Testing
- **Decision**: The web home and live board pages should render lightweight shells and fetch live feeds from the browser, instead of importing API route handlers during server render.
- **Why**: Local browser testing exposed a startup stability risk when page render, provider fan-out, hydration, and client refetch happened together.
- **Implementation**:
  - Removed server-side live feed preloading from `web/src/app/page.tsx` and `web/src/app/swarm/page.tsx`.
  - Switched the web dev script to `next dev --webpack` for a calmer local testing loop while Next 16/Turbopack behavior is evaluated.
  - Pointed `npm start` at the standalone server because `next start` warns when `output: "standalone"` is enabled.

## 2026-05-14: Web Match-Day Parity Pass
- **Decision**: Web match cards and watch pages should mirror the iOS match-day model: scoreboard-first cards, status/source badges, and broadcast sources below the player.
- **Why**: The web app is becoming a usable Fotty client, not only a support/PWA shell, so the core live match experience needs to feel familiar to iOS users.
- **Implementation**:
  - Added a shared `MatchScoreboardCard` web component for Home and Live board match presentation.
  - Replaced older rail/list match cards with iOS-like league/status, team badge, score/VS, source count, and action layout.
  - Added a `Broadcast Sources` section below the web player for direct source switching and clearer P2P source status/change-source affordance.
  - Made football the default web lens by boosting football fixtures in feed ranking, preferring football for the Home featured match, and defaulting the Live board sport filter to Football when available.
  - Replaced the web-style Home hero with a compact Match Center surface and Arena/Insights/Highlights chips that more closely match the iOS MatchHub structure.

## 2026-05-14: Web Support Funnel Before Payments
- **Decision**: Monetization on web should start as a visible support funnel, not a paywall around match discovery or playback.
- **Why**: Fotty needs a monetization path, but the live sports experience should stay match-first while payment links and account entitlements are still being wired.
- **Implementation**:
  - Added a visible Support action to the desktop top bar and a Home support card.
  - Converted the Support page from a conditional "coming soon" page into three always-visible paths: Match-Day Supporter, One-Time Boost, and Venue or Partner.
  - Support actions use configured support/payment links when available and fall back to email or Feedback registration interest when links are not configured.

## 2026-05-14: Web Stability Smoke Tests & Local Event Signals
- **Decision**: Start web hardening with a zero-dependency smoke script and local product/revenue event capture before adding heavier analytics infrastructure.
- **Why**: The web app needs fast confidence checks around fragile routes and needs early signal on support/watch intent before paid account entitlements are built.
- **Implementation**:
  - Added `npm run smoke` via `web/scripts/smoke-web.mjs` to check core routes, support funnel copy, login copy, and football-first feed ordering.
  - Added `trackEvent` in `web/src/lib/analytics.ts`, storing the latest local events in browser localStorage.
  - Wired events for login attempts, watch-match clicks, support funnel clicks, and source-change clicks.

## 2026-05-10: Fast-First VOD Resolution
- **Decision**: Movie and TV playback should return the first native-capable stream instead of waiting for several mirrors.
- **Why**: The resolver was waiting for up to 5 sources while slower providers held 45-second extraction windows, causing long "Finding streams..." delays even after a usable stream had been found.
- **Implementation**:
  - `ContentResolutionService` now cancels provider races after the first VOD source.
  - VOD provider extraction timeouts are bounded to 7-15 seconds by provider.
  - `WebViewRenderer.extractSources` is cancellation-aware so cancelled provider races stop their WebView work promptly.

## 2026-05-10: VOD Playback Gate & Fallback Repair
- **Decision**: Release builds for the standard Fotty target compile with `FOTTY_FULL_ACCESS`; ReviewSafe builds compile with `APP_REVIEW_SAFE`.
- **Why**: Standard Release was falling through to runtime review mode by default, which disabled on-demand movie/TV playback unless a remote integrity check unlocked it.
- **Implementation**:
  - Added explicit compile conditions to both `project.yml` and `Fotty.xcodeproj`.
  - Corrected the movie WebView fallback route from malformed `vidsrc.net/embed/{id}` to `vidsrc.net/embed/movie/{id}`.
  - Added VOD fallback candidates for `vidsrc.to`, `vidsrc.me`, and `multiembed.mov` for both movie and TV episodes.

## 2026-05-10: VOD Stability & Platform Alignment (v1.8.1)
- **Decision**: Formally separate Android (Sports-Only) and iOS (Sports + VOD) project scope in project memory.
- **Decision**: Implement "Handoff Quiescence" in WebViewRenderer.
- **Why**: Prevent the "Infinite Pause/Play" loop caused by the auto-clicker continuing to tap the screen after the video has already started.
- **Implementation**:
    - Scraper now stops all click/tap activity as soon as `video.duration > 0` is detected.
    - Added text-based detection for "WATCH NOW" and "DOWNLOAD" buttons to bypass server gates faster.
    - Expanded sniffer to catch obfuscated `vplayer` and `playlist` URLs.

## 2026-05-09: Playback Pipeline Hardening (v1.6)
- **Decision**: Reduce pre-flight resolution timeouts from ~60s to ~20s.
- **Why**: User was experiencing "cascading timeouts" where the resolution layer took so long that the player never started.
- **Implementation**: 
  - Reduced `StreamWebExtractor` timeouts to 8s.
  - Reduced `URLSession` resource timeouts to 8s.
  - Reduced individual source validation to 5s.
  - Reduced AVPlayer readiness timeout to 7s.
- **Decision**: Implement a "Staggered Parallel Race" for stream resolution.
- **Why**: To achieve sub-10s startup times by racing Web sources against P2P backups, while preventing redundant resource usage once a stream is successfully playing.
- **Implementation**: 
  - Web track starts at `T+0`.
  - P2P track starts at `T+2s`.
  - First successful session cancels all other pending resolution tasks to preserve battery and data.
  - User requested **explicitly** to avoid background monitoring of secondary sources to keep logic "simple and fail-fast" unless reliability issues arise.

## 2026-05-09: Branding Cache-Buster Removal
- **Decision**: Remove the URL-stripping logic in `TeamBrandService`.
- **Why**: It was incorrectly removing required ESPN CDN query parameters, causing logos to "ghost" (disappear).
- **Implementation**: Replaced `URLComponents` manipulation with a safe cache-busting append logic.

## 2026-05-07: PocketBase Migration
- **Decision**: Shift to self-hosted PocketBase for all sports metadata.
- **Why**: Eliminate TheSportsDB rate limits and improve logo accuracy for leagues like NBA, WNBA, and MLB.
- **Implementation**: Added `PBSportsTeam` hardening and manual patch scripts (`fix_missing_wnba.py`).

## 2026-05-01: Broadcast Sources as Primary Switching UI
- **Decision**: Stream changes, including P2P, should happen from the “Available Broadcast Sources” section below the player.
- **Why**: The player chrome should stay focused on playback controls. Users need one obvious place to switch streams.
- **Implementation**: Removed source-switch controls from player chrome; error overlay points back to broadcast source area.

## 2026-04-28: Early Autoplay Arming
- **Decision**: Request playback immediately after handing an `AVPlayerItem` to AVPlayer, then again after readiness.
- **Why**: Some live streams do not start if the app waits until the item is fully ready.
- **Implementation**: Added `requestPlaybackStart` helper in `LivePlayerViewModel`.

## 2026-04-25: Web Embed Video-Level Nudging
- **Decision**: Web embed autoplay should directly nudge detected `<video>` elements in addition to clicking play buttons.
- **Why**: Some embed players ignore or hide normal play buttons.
- **Implementation**: Added direct `video.play()` kick with `playsinline` attributes via Javascript injection.

## 2026-05-09: Appearance Section Consolidation (v1.6)
- **Decision**: Remove the entire "Appearance" section from Settings, including the "Theme Mode," "Compact Mode," and "Reduce Motion" toggles.
- **Why**: These were non-functional placeholders. Removing them ensures the v1.6 Settings Hub is 100% reliable and only contains features that are fully implemented.
- **Implementation**: 
  - Hardcoded `.preferredColorScheme(.dark)` in `FottyApp.swift`.
## 2026-05-09: Cloud-First Strategy (Roadmap v1.7)
- **Decision**: Prioritize PocketBase synchronization for User Profiles and Playback Progress.
- **Why**: To enable a seamless multi-device experience. Users should be able to start a match or movie on an iPhone and continue on an iPad/Mac without losing progress.
- **Implementation**: Will utilize the `SocialCloudStore` and new `CinemaSyncService`.

## 2026-05-09: Notification Core Implementation (v1.6)
- **Decision**: Implement local-only notifications driven by a score-diffing engine.
- **Why**: Provides immediate value for goals and kickoffs without the complexity of a push-notification backend for the initial release.
- **Implementation**: 
  - `NotificationManager` handles `UNUserNotificationCenter` permissions.
  - `LiveScoreService` performs "snapshot diffing" on every poll to detect goals and status changes.
  - Integration with **Spoiler Protection** to mask scores in alert banners.

## 2026-05-09: Actor-Centric Search Implementation (v1.8)
- **Decision**: Re-prioritize v1.8 (Discovery) over v1.7 (Cloud Sync) based on user preference.
- **Why**: Deepening the media catalog provides immediate engagement value.
- **Implementation**:
  - Expanded `TMDBService` to fetch biographical data and combined filmography credits.
  - Added `ActorProfileView` with glassmorphic design and sorted media grids.
  - **UX Refinement**: Transitioned from horizontal scrolls to a **3-column high-density vertical grid** with segmented tabs (Movies/TV) to optimize searchability for large filmographies.
  - **Deep Discovery Loop**: Implemented navigation links from the `MediaDetailView` cast section back to the `ActorProfileView`, enabling circular discovery.
  - Updated `MediaType` enum to support `.person` and ensured exhaustive switch handling in playback and detail views.

## 2026-04-20: Native PiP & Live Activity Support
- **Decision**: Fotty should support Picture in Picture and Live Activities/Dynamic Island where system support allows.
- **Why**: Live sports users expect app minimization without losing playback; adds a premium "native" feel.
- **Implementation**: Integrated `AVPlayerLayerView` PiP bridge and `FottyLiveActivityExtension`.

## 2026-05-10: Fast VOD Native Startup With Web Fallback Kick
- **Decision**: VOD resolution should stop after a small native failover set and embedded web fallback should repeatedly trigger provider play overlays.
- **Why**: Waiting on every mirror made movies/shows slow to start, while some providers could land on a black web player with a visible play overlay and no playback.
- **Implementation**:
  - Cancel provider extraction once at least two native-playable VOD sources are found.
  - Tighten provider extraction timeouts so slow mirrors do not dominate startup.
  - Add cancellation cleanup for WebView extraction.
  - Expand embedded player auto-kick to coordinate taps, visible play/server labels, and repeated short retries before giving up.

## 2026-05-10: VOD Web Fallback Touch Handoff
- **Decision**: Web fallback hints must not cover the whole player surface, and WPlay shell fallback should not loop on a loading frame.
- **Why**: On iPhone, the bottom hint sheet could intercept the real touch it asked the user to perform, while the first WPlay shell candidate could keep retrying instead of advancing.
- **Implementation**:
  - Moved fallback candidates to direct provider routes before the WPlay shell.
  - Added a bounded WPlay shell retry so loading frames advance to the next candidate.
  - Added a Start action that sends a user-initiated playback kick without reloading.
  - Set the WKWebView user agent and direct-provider referers consistently.

## 2026-05-11: Full-Screen VOD Fallback Presentation
- **Decision**: VOD web fallback must use full-screen presentation instead of an iOS sheet.
- **Why**: The rounded sheet presentation constrained the provider player and made a blank player state look like a touch-gate issue.
- **Implementation**:
  - Replaced the web fallback sheet with a full-screen cover.
  - Replaced premature Start/Retry prompts with a non-blocking candidate status while providers are still cycling.
  - Kept Start/Retry only for final fallback failure once candidate cycling has exhausted.

## 2026-05-14: Fresh Focused P2P EPG for Fotty Web
- **Decision**: Fotty web should use a fresh, focused XMLTV guide for P2P sports channels instead of keeping a stale full guide in the repo workspace.
- **Why**: The P2P channel guide is only useful if it tells users what is on now/next. The old local `server/epg/guide.xml` was stale and unnecessarily large.
- **Implementation**:
  - Added `server/epg/filter_fotty_p2p_channels.py` to generate a focused sports/P2P channel list from the upstream guide data.
  - Updated `server/epg/refresh_epg.sh` to rebuild that focused channel list and refresh `server/epg/guide.xml`.
  - Added a daily local automation named "Refresh Fotty P2P TV Guide" to keep the guide fresh.
  - Updated the web EPG API to prefer the fresh local guide in development and to match channel ids that carry real programme rows.
- **Verification**:
  - Deleted the stale guide and generated a fresh 3.7 MB `guide.xml` dated `20260515`.
  - Confirmed the API returns now/next listings for Sky Sports Main Event and ESPN.
  - Rebuilt standalone web and ran the smoke suite successfully.

## 2026-05-20: DirecTV-Style P2P Guide for Fotty Web
- **Decision**: Fotty web should expose a real grid-style TV guide for P2P channels at `/guide`, using the existing XMLTV EPG as a schedule window instead of only showing now/next cards.
- **Why**: The previous guide was only semi-useful for discovery. Users need to scan many channels across time, filter by region, search, and jump straight into playback.
- **Implementation**:
  - Extended `POST /api/epg/guide` with `windowStart` and `windowHours` so the API can return overlapping programmes for a bounded grid window.
  - Added `TVGuideView` with sticky channel rows, half-hour time slots, search, region filters, previous/now/next controls, and direct Watch links.
  - Added `/guide` and promoted it into the web bottom navigation.
- **Verification**:
  - Confirmed the homelab EPG cron exists at `0 4 * * *` via `/home/jelani/acestream/server/epg/run_scheduled_refresh.sh`.
  - Confirmed the deployed EPG proxy reports a fresh local guide at `/data/epg/guide.xml` with cached bytes `3438328`.
  - Deployed `fotty-web:guide-test` as `fotty-web:latest`; public `/guide` returned HTTP 200.
  - Smoke-tested the deployed local API with 164 P2P channels, 78 guide rows for the first 80 channels, 27 exact EPG matches, and 187 scheduled programmes in the current four-hour window.

## 2026-05-20: US/UK-Focused P2P Guide Catalog
- **Decision**: Fotty Web should hide Poland and Russia P2P channels from the web-facing guide/catalog and prioritize US/UK sports channels in ordering and discovery.
- **Why**: The TV guide is more useful as a scan-first US/UK sports surface than as a broad mixed-region channel dump.
- **Implementation**:
  - Filtered Poland/Russia region rows, Cyrillic channel labels, and `.ru` channel labels from `/api/p2p/channels`.
  - Boosted United Kingdom and United States channels in P2P channel ranking.
  - Removed Poland/Russia from the `/guide` region controls and excluded those regions from web EPG map matching.
  - Expanded AceStream discovery queries for more US/UK targets including NFL RedZone, NBC Sports, SEC Network, ACC Network, Big Ten Network, ESPNU, ESPNews, and additional Sky Sports variants.
- **Verification**:
  - Deployed `fotty-p2p-proxy` and `fotty-web`.
  - Confirmed the deployed web catalog removed region-tagged Poland/Russia rows and returned 101 channels before final `.ru` cleanup.
  - Confirmed `/guide` returned HTTP 200 and guide smoke returned 76 guide rows, 25 exact EPG matches, and 289 scheduled programmes in the current four-hour window.

## 2026-05-20: Free-First EPG Expansion Pipeline
- **Decision**: Expand Fotty EPG coverage by auditing free XMLTV sources first, but keep the user-facing guide restricted to `confidence=verified` mappings.
- **Why**: AceStream can provide playable channel streams, but it does not reliably provide programme schedules. The guide needs separate XMLTV schedule data mapped to stream names.
- **Implementation**:
  - Added an EPG source audit script that compares current P2P channel names with existing generator channels and free XMLTV sources, writing candidates to `server/epg/p2p_epg_candidates.json`.
  - Added optional extra XMLTV merging that only imports channels already promoted to verified mappings.
  - Added support for `candidate` and `rejected` mapping states while preserving the rule that only `verified` entries are shown by `/api/epg/guide`.
  - Updated `/guide` to batch EPG requests for all visible channels, sort mapped rows before backup rows, and show a backup divider for unmapped channels.
- **Verification**:
  - Candidate audit found 57 unmapped rows with possible EPG matches, including BT Sport ESPN, Movistar sports channels, Sky Sport F1, SuperTennis, Smart Spor, and DAZN/LaLiga variants.
  - Promoted only the safe Sky Sport F1 fallback mapping; kept BT Sport ESPN candidate-only because the `tvprofil.com` grab returned HTTP 403.
  - Deployed Fotty Web and confirmed `/guide` returned HTTP 200.
  - Smoke-tested deployed guide batching: 95 P2P channels, 88 guide rows returned, 27 exact mappings, and 244 scheduled programmes.
- **Known follow-up**:
  - The homelab four-day and one-day EPG generator runs hit upstream/grabber reliability issues (`tvprofil.com` 403, Movistar certificate errors, and a Node heap/stall late in the grab). Keep the current production guide file until the refresh job is tuned to skip failing sources or split large grabs safely.

## 2026-05-20: Web P2P Live-HLS Stall Recovery
- **Decision**: Fotty Web's P2P player should treat AceStream broker manifests as sparse live HLS and aggressively resume from the live edge after stalls, rather than only restarting HLS loading before playback has begun.
- **Why**: Several P2P streams could start, play roughly ten seconds, drop to black, and repeat while the broker continued serving fresh manifests. That pointed to client-side live edge/stall recovery rather than channel discovery.
- **Implementation**:
  - Reduced the initial buffer gate for web P2P playback and tuned Hls.js live sync closer to the broker's short live window.
  - Added recovery for non-fatal buffer stalls and fatal network errors after playback has already started.
  - Added a short video `waiting` recovery timer that restarts HLS loading and jumps back toward the live sync position when playback drifts too far behind.
- **Verification**:
  - Deployed `fotty-web` successfully through the homelab Docker build.
  - Confirmed deployed `/api/p2p/channels` still returns 95 US/UK-prioritized channels and `/watch/[id]` returns HTTP 200.
  - Checked `fotty-p2p-proxy` logs showing broker manifests continue returning HTTP 200 after startup, with initial segment probes succeeding.

## 2026-05-20: Football-First Match Day Board
- **Decision**: Fotty Web's Live Board should behave more like a football fan's match-day command center, with live matches, followed teams, and imminent kickoffs separated before general upcoming fixtures.
- **Why**: A fan should not have to hunt past future or less relevant cards to find the match that is actually on, and common controls like spoiler protection and guide/tables context need to be reachable from the board itself.
- **Implementation**:
  - Added a match-day control strip with live/soon/tracked-team counts, inline spoiler toggle, and quick links to TV guide and tables.
  - Split the match list into `For you`, `Live now`, `Starting soon`, `Big fixtures`, and `Up next`, with duplicate suppression across sections.
  - Added watch confidence labels to the featured panel and match cards using feed depth and playback health signals.
  - Changed user preference hydration to start from deterministic defaults and load local storage after mount, reducing hydration mismatch risk between devices.
- **Verification**:
  - Deployed `fotty-web` successfully through the homelab Docker build.
  - Smoke-tested the public mobile `/swarm` page with Playwright: page loaded without console errors, and the new control strip, TV guide link, and confidence labels were present.

## 2026-05-21: Web Playback Stability Guardrails
- **Decision**: Fotty Web should expose stream status diagnostics, keep event stream lookup on the same watch-token path as playback, and recover from slow-loading event embeds by moving to the next ranked backup feed.
- **Why**: Playback issues were showing up differently across devices and browsers. Users need clearer device-level recovery, while the app needs to avoid silently sitting on a blank or blocked feed when alternates are available.
- **Implementation**:
  - Updated event stream lookup to request a watch token before calling `/api/live/streams`, while still sending session headers as fallback.
  - Added a watch-page Status panel showing mode, access, lookup state, feed count, selected feed, iframe state, last check time, and current error.
  - Added event iframe load/error tracking and a timed backup switch when a provider frame does not load quickly.
  - Added a Settings action to refresh the current device by clearing Fotty API caches, updating service workers, and reloading without signing the user out.
- **Verification**:
  - Ran focused ESLint on the changed web files; only the existing P2P warmup set-state warning remains.
  - Ran the local production web build successfully, with the existing Turbopack EPG NFT warning unchanged.
  - Deployed `fotty-web` successfully through the homelab Docker build and smoke check.

## 2026-05-22: Operator-Focused Admin Access Dashboard
- **Decision**: The Fotty admin access page should work as an operator dashboard, not only a raw account edit form.
- **Why**: Manual WhatsApp/bank-transfer activation needs fast answers about who is active, expiring, expired, lifetime, or on a short Match-Day pass.
- **Implementation**:
  - Added summary cards for visible accounts, active access, expiring soon, expired, and lifetime accounts.
  - Added access filters for All, Active, Expiring, Expired, Lifetime, Match-Day, Plus, and Free.
  - Added status badges and admin-note snippets to the account table.
  - Added selected-account summary cards and quick note templates for common payment/admin situations.
- **Verification**:
  - Ran focused ESLint on `AdminAccessDashboard.tsx`; only existing React set-state-in-effect warnings remain.
  - Ran the local production web build successfully, with the existing Turbopack EPG NFT warning unchanged.
  - Deployed `fotty-web` successfully through the homelab Docker build and smoke check.

## 2026-06-02: Production UX Trust Cleanup
- **Decision**: Fotty Web public routes should use one product voice, one clear next action per page, and a conservative fixture-name quality gate before live data reaches UI.
- **Why**: Paid-user and World Cup readiness depend on trust. Rough provider abbreviations, duplicated featured fixtures, dead guide grids, prototype-style legal copy, and passive empty states make the product feel stitched together instead of reliable.
- **Implementation**:
  - Added a centralized public fixture-name quality gate that converts rough all-caps provider tokens to `Fixture details updating` instead of leaking names such as `PP v San Diego Padres`, `Boston Red Sox v BO`, `WN v Miami Marlins`, or `AD v LAD`.
  - Suppressed duplicate featured fixtures in Live Board personalization.
  - Hid TV Guide quick-pick rails and grids when there are no useful rows, leaving one intentional fallback state.
  - Reorganized Settings into Account, Match Day, Device, and Support.
  - Replaced Saved and Teams one-off empty copy with shared fallback states and clear Live Board / World Cup actions.
  - Rewrote plans, Privacy, and Terms copy to sound production-ready and focus on match-day convenience, reminders, source organization, support, and account features.
- **Verification**:
  - Ran `npm run build` successfully in `web`.
  - Smoked local production routes on port `3020`: `/`, `/swarm`, `/guide`, `/tables`, `/world-cup`, `/watch/test-source`, `/welcome`, `/settings`, `/subscribe`, `/teams`, `/favorites`, `/help`, `/privacy`, and `/terms`.
  - Browser-audited core routes for public prototype/MVP/concept copy and blank-body failures.
  - Confirmed `/api/matches` no longer exposes the known bad fixture-name patterns; rough rows fall back to `Fixture details updating`.
  - Deployed `fotty-web` to the homelab and smoked the same public routes on `https://fotty.pixel-invoice.com`; all returned HTTP 200 and the live match feed still reported zero known bad fixture-name patterns.

## 2026-06-11: Native iOS World Cup Mode Seed
- **Decision**: Fotty iOS should include a native World Cup mode with seeded published fixtures and groups, independent of provider feed reliability.
- **Why**: World Cup readiness cannot depend on the live provider returning clean football rows at the exact moment users open the app; the app must still show the opening schedule, groups, and a watch-path entry point.
- **Implementation**:
  - Added a World Cup football league tab and classification for known 2026 World Cup national-team pairings.
  - Seeded the opening 24 fixtures and all groups into the iOS dashboard/live feeds while filtering non-football World Cup noise.
  - Added a native dashboard World Cup section with Today, Schedule, Groups, and Watch views, plus guide/watch actions.
  - Reworked the section into a premium tournament module with a marquee next-match panel, team medallions, tournament stats, and richer group tiles.
- **Verification**:
  - Ran unsigned generic iOS Debug build successfully.
  - Ran signed Debug device build successfully for the connected iPhone 15 Pro Max.
  - Installed and launched `com.jelani.Fotty` on the connected iPhone 15 Pro Max.

## 2026-06-11: Admin Account Create Handles PocketBase Username Requirement
- **Decision**: Fotty Web admin account creation should always send a generated PocketBase username and preserve field names in validation errors.
- **Why**: PocketBase can reject auth record creation with a generic `Missing required value.` message when the `users` collection has a required field such as `username`; the admin UI only collected email/name/password, making the issue unclear.
- **Implementation**:
  - Generate a safe unique username from the email when creating PocketBase users.
  - Include the generated username in both full and minimal create-account payloads.
  - Prefix PocketBase validation messages with the failing field name.
- **Verification**:
  - Ran focused ESLint on the changed admin/PocketBase server files.
  - Ran local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.

## 2026-06-11: Admin Dashboard Falls Back To Local Grants When PocketBase List Is Forbidden
- **Decision**: Fotty Web admin users should show local admin grants when PocketBase user listing fails, instead of hiding known accounts because `POCKETBASE_ADMIN_TOKEN` exists.
- **Why**: Production had 2 local grants on disk while PocketBase user listing returned `403`. The dashboard was configured for PocketBase mode and therefore showed an empty/failed account list rather than the existing local accounts.
- **Implementation**:
  - `/api/admin/users` now falls back to `admin-grants.json` when PocketBase listing fails and local grants exist.
  - Admin create requests include the selected source so fallback-local mode creates local grants instead of attempting PocketBase.
- **Verification**:
  - Confirmed production has a PocketBase admin token, PocketBase list returns `403`, and `.data/admin-grants.json` contains 2 users.
  - Ran focused ESLint and local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
- **Follow-up**:
  - Replace or widen the production PocketBase admin API key so the dashboard can list PocketBase `users`; the fallback keeps local grants visible but does not fix PocketBase key permissions.

## 2026-06-11: Web Mobile Watch Viewport And Playback Recovery
- **Decision**: Fotty Web watch routes should scroll naturally on phones, use small viewport units for mobile player height, and expose explicit playback retry/recovery paths.
- **Why**: Mobile Safari browser chrome and fixed `dvh` layouts were making the watch page feel clipped, while desktop/mobile playback failures could leave users stuck at a generic unavailable state during match-day use.
- **Implementation**:
  - Replaced full-page mobile `h-dvh`/locked overflow on the watch route with `min-h-[100svh]`, horizontal overflow protection, and desktop-only fixed-height player layout.
  - Reduced the mobile video stage height and kept watch details visible below the player instead of clipping them inside an overflow-hidden panel.
  - Added HLS token/session resolution, longer live-buffer tolerances, live-edge recovery, fatal retry limits, and a visible `Retry stream` action in the P2P player.
  - Sent autoplay-normalized event embed URLs into the iframe, not only the external `Open feed` link.
  - Made the paid access gate respect `100svh` and safe-area padding on mobile.
- **Verification**:
  - Ran focused ESLint on watch/player files; only existing React compiler set-state-in-effect warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
  - Smoked `https://fotty.pixel-invoice.com/swarm`, `/watch/test-source`, `/api/matches`, and `/api/p2p/channels`; pages returned 200, matches returned 101 rows, and P2P channels returned 130 rows.
- **Follow-up**:
  - Real-device/browser visual QA is still required because Codex Browser policy blocked both localhost and the production Fotty domain during this pass.

## 2026-06-12: Chrome HLS Stall Watchdog
- **Decision**: Fotty Web's HLS.js player should detect Chrome stalls where playback has started but the playhead stops without a fatal HLS error.
- **Why**: Some streams continued in Safari/Firefox but started and then stopped in Chrome, which uses the HLS.js/MSE path and can sit in a stalled non-fatal state.
- **Implementation**:
  - Added playhead progress tracking while P2P playback is active.
  - Added a Chrome/HLS watchdog that restarts HLS loading, jumps back to the live edge when needed, recovers media errors on repeated soft stalls, and performs a harder loader restart for long stalls.
  - Kept the watchdog inactive before playback starts, after user pause, or when a real playback error is already shown.
- **Verification**:
  - Ran focused ESLint on `VideoPlayer.tsx`; only existing React compiler set-state-in-effect warnings remain.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
  - Smoked `https://fotty.pixel-invoice.com/swarm`, `/watch/test-source`, `/api/matches`, and `/api/p2p/channels`; pages returned 200, matches returned 95 rows, and P2P channels returned 127 rows.
- **Follow-up**:
  - Verify on real Chrome with a stream that previously stopped; browser automation was not used because prior Codex Browser policy blocked the Fotty domain.

## 2026-06-13: World Cup Group Tables Consume Fixture Results
- **Decision**: The World Cup tab should compute group tables from World Cup fixture scorelines instead of rendering static team lists.
- **Why**: The group view showed every team as a placeholder `Fixture` row even after tournament results existed, making the World Cup hub feel unfinished and leaving tables disconnected from match results.
- **Implementation**:
  - Added World Cup group table calculation from `ScrapedMatch.score`, including P/W/D/L/GF/GA/GD/points/form and group-draw-order tie fallback.
  - Added confirmed fallback result seeds for the opening completed fixtures so tables show useful results while the current Fotty match feed is not carrying World Cup scores.
  - Replaced the Groups placeholder cards with real standings tables plus scoreline rows.
  - Added an actual fixture calendar to the Schedule tab alongside tournament milestones.
- **Verification**:
  - Ran focused ESLint and TypeScript checks on World Cup files successfully.
  - Ran the local production web build successfully.
  - Deployed `fotty-web` to the homelab/public site successfully.
  - Smoked `/world-cup`, `/world-cup?tab=groups`, and `/world-cup?tab=schedule`; all returned 200.
  - Confirmed production group HTML includes `4 results in tables`, Mexico 2-0 South Africa, South Korea 2-1 Czechia, and updated Group A rows.
- **Follow-up**:
  - Wire a live World Cup results provider into `/api/matches` or a dedicated World Cup API so result seeds can be replaced by automatic score ingestion.

## 2026-06-13: P2P Broker Recovers Frozen FOX Sports 2 Live Playlists
- **Decision**: Fotty P2P playback should treat a frozen live HLS media sequence as a broker/session health problem, but only after a recent manifest refresh proves the sequence is truly stuck.
- **Why**: FOX Sports 2 HD could show peers, speed, buffer, and downloadable old segments while Chrome sat at buffering because the playlist stopped advancing. The previous recovery path reused the same CID session and could over-restart Ace after quiet gaps, eventually driving playback manifests into `403`.
- **Implementation**:
  - Added force-new broker session support from the web watch retry path through `/api/stream/session` to the P2P proxy.
  - Added a startup decode watchdog in the web HLS player so a ready-looking source that never decodes triggers session recycling.
  - Preserved `Range`, `Content-Length`, `Content-Range`, and `Accept-Ranges` through the web segment proxy for Chrome/HLS.js.
  - Made live media-sequence manifests refresh without a stale revalidation grace window.
  - Changed frozen-sequence detection to require a recent manifest check, reset retry budget after successful prepares, and treat Ace playback `manifest_403` as retryable.
  - When a frozen sequence is proven, the broker forces a fresh Ace engine playback session and waits briefly for the refreshed manifest before returning a 503.
- **Verification**:
  - Ran focused ESLint on web watch/player/session files; only existing React compiler set-state-in-effect warnings remain.
  - Ran `npx tsc --noEmit --pretty false` and local production web build successfully.
  - Ran `python3 -m py_compile server/p2p_proxy_service.py` successfully.
  - Deployed `fotty-web` and `fotty-p2p-proxy` to the homelab/public site successfully.
  - Confirmed FOX Sports 2 HD is listed by the public web P2P API.
  - Confirmed two force-new session requests for FOX Sports 2 return different broker session IDs.
  - Confirmed the public web manifest for FOX Sports 2 stayed HTTP 200 and advanced after a quiet gap (`883 -> 885 -> 888 -> 894`), and segment range requests return HTTP 206 with `video/mp2t`, `Content-Range`, and `Accept-Ranges`.
- **Follow-up**:
  - Add an automated Chrome/HLS smoke that asserts media sequence movement and first-frame decode for pinned World Cup channels.

## 2026-07-10: Football Matches Proxy And Watch Recovery Extraction
- **Decision**: Mobile football-data.org schedule calls prefer Fotty Web `/api/football/matches` (server-held key), and event-embed failover timers live in a tested recovery helper/hook rather than inline watch-page effects.
- **Why**: Keeping the football-data token only on the web host reduces mobile binary secret exposure; extracting failover selection/timeout arming makes backup rotation testable without mounting the full watch page.
- **Implementation**:
  - Added `force-dynamic` `/api/football/matches` with query allowlisting and upstream URL builder tests.
  - Wired iOS `FootballService` and Android `FootballRepository` / `MatchRepository` to prefer the proxy (direct API remains fallback when a local key exists).
  - Extracted `watch-event-recovery` helpers + `useEventPlaybackRecovery`; `WatchPageClient` uses them for load/start failover.
- **Verification**:
  - Web unit tests: 30 passing (includes football URL builder + event recovery).
  - Android `:app:compileDebugKotlin` after DI wiring.
- **Follow-up**:
  - Deploy web with `FOOTBALL_DATA_API_KEY` before relying on mobile proxy in production.
  - Rotate previously committed credentials; run sustained P2P e2e with `FOTTY_P2P_E2E_CID`.

## 2026-07-10: Playback And Proxy Boundaries Fail Closed
- **Decision**: Caller-controlled media proxy targets must match explicit upstream allowlists, embed playback may only become “started” from real player events, and runtime credentials must not have committed defaults.
- **Why**: The broker segment endpoint and embed HLS endpoint could be abused as broad server-side fetchers, the web player treated an iframe timer as proof of playback, and committed provider/default credentials increased compromise and rotation risk.
- **Implementation**:
  - Added exact-origin validation to the Flask segment proxy and strict HTTPS host-suffix validation to the web embed HLS proxy.
  - Replaced timer-based embed success with validated `postMessage` playback events from the proxied player bridge; errors and stalls now enter the existing backup flow.
  - Split client-safe paid-plan checks from server-only HMAC billing code so Webpack development builds do not bundle `node:crypto`.
  - Removed known P2P, TMDB, football-data, RapidAPI, and API-Football credential literals from current source and moved local mobile values to gitignored build configuration.
  - Made server CI install the broker runtime dependencies and verify the broker imports before tests; serialized web unit tests for deterministic execution.
  - Made watch/auth API routes `force-dynamic` in source; removed Docker sed patching; static FTP export uses `npm run build:static` only.
- **Verification**:
  - All 46 server tests and all 23 web unit tests passed.
  - Web TypeScript, focused playback lint, production web build, Android Kotlin compilation, and iOS simulator build passed.
  - Deterministic Playwright coverage passed for a paid event embed receiving real bridge start/pulse events without remounting.
  - Repository scan found none of the removed credential literals in the current working tree.
- **Follow-up**:
  - Rotate previously committed credentials; removal from HEAD does not revoke Git-history or released-binary copies.
  - Run sustained P2P browser playback against a production-like broker (`FOTTY_P2P_E2E_CID`).

## 2026-07-10: M0 Release Safety Regressions
- **Decision**: Broker crash paths must always preserve structured JSON responses, production playback tests require explicit opt-in credentials, and canonical watch-route helpers must be exercised from their real implementation.
- **Why**: Undefined error logging could mask the original broker exception, a production smoke password was committed in test source, and an embed URL unit suite plus canonical route implementation were outside the default regression contract.
- **Implementation**:
  - Removed undefined `pulseLog` calls and added structured 500 handling for unexpected segment-fetch failures.
  - Added manifest and segment structured-500 integration regressions.
  - Gated the production playback E2E behind `FOTTY_RUN_PROD_PLAYBACK_E2E=1`; credentials, active CID, and endpoints now come from environment variables.
  - Switched the production smoke URL to `/watch/index?cid=...`, extracted the pure watch-route builder, tested P2P/event canonical URLs, and wired `embed-url.test.mjs` into `test:unit`.
- **Verification**:
  - All 43 P2P proxy tests and all 34 web unit tests passed.
  - The production Next.js build, changed-file ESLint, and whitespace checks passed.
  - Repository-wide ESLint remains blocked by 10 existing errors outside the M0 files.
- **Follow-up**:
  - Rotate the exposed production smoke-user password in PocketBase before enabling the gated production test.

## 2026-07-10: M1 Attempt-Scoped Playback Recovery
- **Decision**: Web playback success requires decoded playhead progress, and one attempt-scoped controller owns event-feed switching or P2P session recycling after player adapters report typed facts.
- **Why**: Iframe loads, `play()` resolution, and `playing` events could previously suppress recovery without proving frames advanced; nested HLS, media-element, and parent retries could amplify into remount storms; native Safari HLS lacked the Chrome watchdog path.
- **Implementation**:
  - Added a pure playback reducer with attempt IDs, fault taxonomy, strict late-event rejection, mode-specific recovery actions, and bounded budgets.
  - Event embeds now mark success only after the injected bridge observes advancing `currentTime`, decoded dimensions, and ready media data. Direct-provider fallback no longer counts as playback proof.
  - Reduced HLS fatal retries to two and media-element recovery to one startup/three live attempts; parent P2P session recycling is capped at two.
  - Replaced the Chrome-only stall loop with one media watchdog used by HLS.js and Safari native HLS; both attempt throttled, buffer-preserving soft recovery before bounded media reload.
  - Canonical P2P E2E navigation now uses `/watch/index?cid=...`.
- **Verification**:
  - All 42 web unit tests passed, including controller generation/budget, decoded-progress, embed-bridge, and native-HLS watchdog regressions.
  - Deterministic watch Playwright coverage passed: four tests passed and the real-broker test skipped without `FOTTY_P2P_E2E_CID`.
  - TypeScript and the production Next.js build passed; focused playback lint has no errors (existing warnings remain).
- **Follow-up**:
  - Run the real Chromium P2P test with an active staging CID and verify native Safari playback on a physical Apple device before production promotion.

## 2026-07-10: Pre-Deployment Dual-Browser Playback Gate
- **Decision**: Chrome and WebKit are required CI browser projects, live P2P tests require decoded dimensions plus advancing playhead, and broker credentials must never be redirected into browser-visible manifest URLs.
- **Why**: The previous Chromium-only deterministic gate missed Safari behavior; a live production-build test exposed missing watch-token propagation, cross-origin auth-header failures, stale session manifests, and an `api_password` query in the browser network path.
- **Implementation**:
  - Added WebKit to Playwright and CI browser installation, blocked service workers in deterministic tests, and refreshed stale home/login/watch assertions.
  - Added bounded event-feed exhaustion coverage and verified no feed-rotation loop after all generated backups fail.
  - Propagated short-lived watch tokens to P2P session, status, and health requests.
  - Kept P2P API credentials server-side by serving the manifest through `/api/stream`; session-manifest 503s now fall back to the CID-bound signed public manifest.
  - Prevented HLS.js from adding account headers when a signed `watchToken` already authorizes the media URL.
  - Fixed repository lint errors and reduced the gate to 48 warnings, below the enforced maximum of 50.
- **Verification**:
  - Server: 48 tests passed.
  - Web: 42 unit tests, TypeScript, lint, and production build passed.
  - Deterministic Playwright: 26 passed across Chromium and WebKit; four environment-gated real/production cases skipped as designed.
  - Deployment-like P2P playback decoded the same ESPN HD source in both engines: Chromium 1280×720 and WebKit 1280×720, `readyState=4`, advancing playhead.
  - A separate 1920×1080 source decoded in WebKit but not Chromium, confirming source/codec compatibility remains source-dependent.
- **Follow-up**:
  - Run the opt-in production PocketBase sign-in/playback test with rotated credentials.
  - Confirm WebKit behavior on a physical iPhone/iPad and run a longer multi-source soak before production promotion.

## 2026-07-10: Playback Trust And AceStream Operations Hardening
- **Decision**: Provider players run in an opaque sandbox, media URL tokens contain no PII and expire after ten minutes, the homelab Compose file is the sole production definition, and AceStream API events are part of the broker contract.
- **Why**: Same-origin provider HTML could access Fotty browser state; four-hour email-bearing URL tokens leaked identity and reusable authorization; duplicate deploy/scraper paths caused drift; generic manifest failures hid missing `proxyServer` entitlement and codec/segmenter failures.
- **Implementation**:
  - Applied iframe and CSP sandboxes without `allow-same-origin`; the bridge accepts opaque-origin messages only from the exact mounted iframe window.
  - Replaced email/user-ID token payloads with an authenticated AES-GCM envelope containing a one-way subject, nonce, and paid entitlement; shortened lifetime to ten minutes and invalidated the legacy payload shape.
  - Required broker authorization for catalog, search, metrics, and dashboard routes.
  - Made `homelab-docker-compose.yml` canonical: two Gunicorn workers × 16 threads, loopback Redis/Gunicorn bindings, no duplicate scraper, no AceStream remote-access flags, and bounded evidence-backed prewarming.
  - Updated the deploy helper to use Compose, verify `/health`, and fail when control ports 6379/6878/8006 listen beyond loopback.
  - Enabled AceStream API events and stop notifications; typed `missing_option`, `segmenter_failed`, `download_stopped`, and codec events are persisted in broker timelines and private metrics.
  - Added a five-minute free-versus-Proxy-Server baseline capture tool.
- **Verification**:
  - All 46 broker tests, 42 web unit tests, TypeScript, lint, production build, and Compose parsing passed.
  - Deterministic Playwright passed 26 tests across Chromium/WebKit; four opt-in production cases skipped.
  - Real ESPN HD playback decoded at 1280×720 with `readyState=4` and advancing playhead in Chromium and WebKit.
  - Current free-engine aggregate baseline remains below promotion gates: manifest p95 17.592s and segment 2xx rate 81.62%.
- **Follow-up**:
  - Deploy the canonical stack in a maintenance window, verify loopback listeners, and repeat the three-source five-minute soak.
  - Activate one month of an official plan containing `proxyServer`, then capture the paid comparison window; Premium cannot be activated from source code.
  - Run physical iPhone/iPad playback and controlled AceStream/Redis restart tests before shared staging.

## 2026-07-10: Live Feed Identity Includes Playback Availability
- **Decision**: Home-feed refresh identity includes event-source and playback fields; active fixtures retain their last playable mapping across transient empty/incomplete provider refreshes; finished fixtures are never hero fallbacks.
- **Why**: The previous score/status-only fingerprint treated a newly attached StreameX source as unchanged, leaving live cards rendered as inert articles and allowing a high-ranked finished World Cup fixture to remain in the hero.
- **Implementation**:
  - Added source identity, playback type, source count, and kickoff time to `matchFeedSignature`.
  - Added bounded mapping preservation for active fixtures while explicitly refusing to revive finished fixtures.
  - Prioritized any genuinely live fixture above upcoming/fallback content and removed finished matches from the final hero fallback.
- **Verification**:
  - All 45 web unit tests, TypeScript, and lint passed.
  - Focused Chromium and WebKit Playwright coverage passed.
  - The running home page selected Spain v Belgium, exposed a signed event watch link, and a live game card opened the canonical watch route.

## 2026-07-10: Watch Page Carries Every Provider Source, Not Just The Top One
- **Decision**: A fixture's watch link and player expose all provider broadcaster/language links, instead of collapsing to the single highest-priority source.
- **Why**: The matches feed picked one `eventSource` by fixed `SOURCE_PRIORITY` (echo/delta/golf/alpha/admin) and only enumerated `streamNo` variants of that one source, so multi-broadcaster events (e.g. Spain vs Belgium) surfaced only the Spanish feed even though the provider listed several.
- **Implementation**:
  - Added `eventSources` to `ScrapedMatch`; `fixtureToMatch` populates all playable provider links ordered by source priority and deduped.
  - Added `web/src/lib/watch-event-sources.ts` (encode/decode/dedupe/key) and serialized the full set into a `sources` watch-URL param from both the client (`buildWatchHref`) and server (`buildServerWatchHref`) link builders; the World Cup merge retains `eventSources` via spread.
  - Reworked `useEventStreams` to fetch every source in parallel and merge into one feed list (per-source numbered variants, deduped by embed URL); single-source matches keep their four-deep synthesized backups, and each source contributes its primary embed when detail lookups return nothing.
  - `eventEmbedURL` now derives from the selected stream's own source/id.
- **Verification**:
  - 49 web unit tests (incl. new `watch-event-sources` round-trip/dedupe coverage), TypeScript, and lint passed.
  - Live dev `/api/matches` showed 49 fixtures with multiple sources; Spain v Belgium exposed echo/golf/admin, and both SSR HTML and the hydrated home page emitted the full `sources` param for Spain and Miami.

## 2026-08-02: Web Watch needs playback Worker for iOS stream parity
- **Decision**: Every non-P2P catalog stream iOS can play (StreamEx/VipLeague/`echo`/`delta`/…) must be playable on getfotty.com via the same Referer + HLS proxy model. Static FTP alone cannot do that; ship `web/workers/playback` and set `NEXT_PUBLIC_FOTTY_API_BASE` at `build:static`. Client must use the remote API on getfotty.com when configured (do not short-circuit to bare `embed.st`). Source priority matches iOS (`echo` first).
- **Why**: Browsers cannot inject StreamEx Referer or segment headers; iOS WKWebView + `LocalStreamProxy` can. Direct iframes fail with `hls:networkError_manifestLoadError`.
- **Verification**: With Worker + `NEXT_PUBLIC_FOTTY_API_BASE`, Watch loads `/api/embed/player` from the Worker and feeds start; without it, site synthesizes Fotty 1–4 direct embeds only (degraded).

## 2026-08-02: Remove EPG / TV Guide infrastructure
- **Decision**: Delete all XMLTV/EPG product code — web `/api/epg`, guide/swarm routes and UI, iOS `EPGDataStore`, and the entire `server/epg/` tree (including the vendored iptv-org generator). No redirect stubs for `/guide` or `/swarm`. Keep `web/src/lib/stream-guide/` (match feed ranking, not TV EPG).
- **Why**: Homelab/P2P channel catalog is retired; EPG only served that Guide surface and added launch/watch dead work.
- **Verification**: No `epg` / `EPGDataStore` / `xmltv` hits under `web/src` or `Fotty/`; `server/epg/` absent.

## 2026-08-02: Retire World Cup product surfaces
- **Decision**: Remove all World Cup hubs, seeds, tournament-focus fetch targeting, nav entries, APIs, ranking boosts, and route stubs from iOS and getfotty.com. Do not keep `/world-cup` redirect pages.
- **Why**: The tournament is over; continuing to ship WC seeds, tabs, and priority ranking distorts Home/Schedule toward a finished event.
- **Implementation**:
  - iOS: deleted `WorldCupTabView` / `WorldCupDataLoader`; match lists use provider events only; restored normal multi-league football focus.
  - Web: deleted WC view/libs/hooks/APIs/routes; stripped home/schedule/discover WC rails; removed BottomNav entry and sitemap path.
- **Verification**: Zero `World Cup` / `WorldCup` / `world-cup` product hits under `Fotty/` and `web/src`.

## 2026-08-02: iOS Home badges — persist Nexus crests in SwiftData cache
- **Decision**: `MatchCacheItem` stores `homeBadge` / `awayBadge` tokens; cache reload must not force `badge: nil`. `FlagSquircleBadge` observes `TeamBrandService` so async brand resolve re-renders. Home cards (`LiveEventCard`, `HeroMatchCarousel`, `ForYouLiveCard`) also fall back to `TeamBrandService` like Social/MatchHub.
- **Why**: Home showed initials after cache round-trip even when StreamEx sent crest tokens; MatchHub/Social already had working crest paths.

## 2026-08-02: Web club badges use StreamEx crest URLs again
- **Decision**: Stop discarding long `streamed.pk` badge URLs in `teamFlagDisplay`. Show the same StreamEx crest tokens the iOS app resolves via `AnalyticalDataEngine.imageURL`.
- **Why**: Web was forcing initials because long encoded badge URLs were treated as placeholders; those URLs are valid club crests.

## 2026-08-02: Retire web Guide / Swarm / P2P channel catalog
- **Decision**: Remove TV Guide, Live Board (`/swarm`), and P2P channel rails from getfotty.com nav and Discover. Routes deleted (not redirected). Channel APIs return empty; copy points to Home/Discover/Schedule.
- **Why**: Those surfaces depended on the retired AceStream/homelab channel catalog. Site is fixtures-only (StreamEx match list → Fotty 1/2/… feeds).

## 2026-08-02: Web match feed = StreamEx catalog (same as iOS)
- **Decision**: getfotty.com loads fixtures from the **StreamEx / Nexus** schedule (`streamex.net` / mirrors), the same catalog the iOS StreamEx + VipLeague modules use. Strip retired P2P `admin` sources. Do not call the dead scraper API.
- **Why**: Homelab is gone; static export previously short-circuited to `[]`. App already watches via StreamEx/VipLeague web embeds — site should match.
- **Mapping**: `delta`→StreamEx, `echo`→VipLeague; Score808 remains an embed-domain filter in the app modules. Watch on static FTP synthesizes `embed.st` URLs when `/api/live/streams` is unavailable.

## 2026-08-02: Homelab retired — getfotty.com FTP only
- **Decision**: The Acer/homelab stack (`100.116.91.102`, `fotty.pixel-invoice.com`, scraper/P2P tunnels) is **gone**. Do not SSH, deploy via `web-deploy-homelab.sh`, or default web clients to pixel-invoice hosts. Public web deploy is **FTP to getfotty.com** only (`npm run build:static` → upload `web/out/`).
- **Why**: Operator shut down the lab; leftover defaults and deploy scripts would waste time and break builds against dead hosts.
- **Implementation**:
  - `getPublicFottyApiBase()` returns empty unless `NEXT_PUBLIC_FOTTY_API_BASE` is set at build time.
  - `web/DEPLOY.md` documents FTP-only hosting.
  - 2026-08-02 static export uploaded to Octavia FTP (416 files).

## 2026-08-02: Web companion — app-first alignment pass
- **Decision**: getfotty.com stays coverage; iOS is primary. Web Home gets **On-now glance**; `/search` ships **DiscoverViewV2** (not classic search); welcome/PWA shortcuts stop leading with Live Board/`/swarm`.
- **Why**: Site still read like a P2P/homelab product after the app retired AceStream and added glance + modules.
- **Next**: further demote `/swarm` in nav; replace build-time match feed now that scraper host is gone.

## 2026-08-02: Watch Now reliability + smarter On-now + VipLeague module
- **Decision**: Rank broadcast sources by `LiveSourceHealthStore` (success/latency/stalls + last-good provider per sport/league). On-now diversifies sports, biases followed teams, adds **Surprise**. Seed **VipLeague** (`echo`) as the third web module beside StreamEx + Score808. getfotty.com sync deferred — app remains primary.
- **Why**: Elevate value without bringing the homelab back; make Watch Now feel inevitable and discovery glanceable.

## 2026-08-02: P2P/AceStream retired for now + On-now glance
- **Decision**: Strip P2P from featured stream modules and skip homelab P2P resolution unless a P2P module is explicitly enabled. Home gains a compact cross-sport **On now / soon** glance strip under the masthead.
- **Why**: Operator is done with AceStream self-hosting for now (power/cost). Users still need a tiny “what can I watch right now?” signal that ignores the active sport filter.
- **UI**: `OnNowGlanceBar` — ~32pt chips, not a second rail or side panel.

## 2026-08-02: Stream modules restored in Settings
- **Decision**: Settings → **Stream modules** manages StreamEx / Score808 manifests. Fresh installs seed StreamEx + Score808 enabled.
- **Why**: The plugin UI existed only in a stash (`81081c5`) and never shipped on HEAD, so users couldn’t see or manage add-ons while web catalog resolution still ran invisibly.
- **Path**: `SettingsScreen.streamPluginsSection` → `StreamPluginsSettingsView`; resolvers via `StreamPluginRegistry` + `NativeBridgePluginAdapter`.

## 2026-08-02: Drop iPad Home side rail — full-width stack
- **Decision**: Home on iPad uses the same full-width vertical stack as iPhone (hero → Live rail → fixtures). No “Up next” / Live&soon side column.
- **Why**: The narrow right rail left a tall void under a short card stack and pulled weight to one edge; it read as a bolted-on panel, not cinema editorial.
- **Keep**: Regular size class still gets a 2-column fixture grid under the full-width hero.

## 2026-08-09: StreamEx in-play games pin to Live without scoreboard match
- **Decision**: `HomeMatchPriority.isLive` uses API-Football when available; otherwise treats kickoff-started + within **2h** as live (StreamEx friendlies/smaller leagues). Supersedes the earlier 3h window.
- **Why**: Liverpool vs Monaco was on the Nexus live feed but unmatched in LiveScoreService, so it never entered the Live rail and sank mid football list. 3h was wider than a real match and left finished friendlies marked live.
- **Verification**: Home → Football → in-progress StreamEx games appear under Live / hero, not buried in Today; drop off ~2h after kickoff when no scoreboard status.

## 2026-08-09: Score808 hotel-from-donor restored (web embed only)
- **Decision**: When Nexus omits `hotel`, synthesize `embed.st/embed/hotel/{donorId}` from delta/echo. Prefer Score808 web embeds over native StreamEx extracts. Never native-HLS-extract hotel. Reject ~1–2KB empty player stubs during web-embed validation.
- **Why**: Hotel shares the live feed with StreamEx donor ids (full ~600KB player config). An intermittent empty stub caused a false “dead shell” conclusion; native extract of that stub surfaces `hls:networkError_manifestLoadError` while WKWebView playback works.
- **Supersedes**: “Score808 only when Nexus has hotel”.
- **Verification**: Watch Now → Score808 #1 selected first as web embed; plays; Change Source still lists StreamEx.

## 2026-08-09: Safari-parity playback (app bug, not source bug)
- **Decision**: Watch Now returns Score808/StreamEx `embed.st` URLs immediately (no headless extract / stub probe on the critical path). `LiveWebEmbedPlayerView` loads the site origin first, then navigates to the embed so referrer matches Safari.
- **Why**: Score808 and StreamEx play fine in Safari. Stalls, black screens, and `manifestLoadError` came from Fotty’s resolve/player pipeline (Referer stripping, extract timeouts, aggressive scripts), not from the sources.
- **Verification**: Watch Now opens in ~1s; Score808 and StreamEx play in-app without hanging on “Looking for a playable stream…”.

## 2026-08-09: Player sources = StreamEx + Score808 only (no P2P UI)
- **Decision**: Remove Browse P2P Channels from the player. Watch Now resolves web-only and lists **StreamEx** + **Score808** only. VipLeague/P2P modules are stripped from seeds/featured.
- **Why**: Homelab AceStream is gone; Browse P2P was a dead end. Operator wants the source list to match the two active modules.
- **Implementation**: `LivePlayerView` P2P browse removed; `performResolution` skips P2P race; `StreamPluginProviderMatching.activePlayerProviderCodes`; registry strips echo/p2p leftovers.
- **Verification**: Rebuild → Watch Now → Available Broadcast Sources shows only StreamEx/Score808 rows; no Browse P2P control.

## 2026-08-09: StreamEx autoplay kick + Score808 visibility
- **Decision**: After first successful embed start, only call `video.play()` — never re-tap StreamEx UI (toggle leaves stream paused). Watch Now must scan **all** Nexus families for web embeds before returning; Nexus `hotel` is labeled **Score808**.
- **Why**: Post-start UI kicks toggled StreamEx into a stuck pause; early return after 2 StreamEx native extracts hid Score808/hotel from Change Source entirely.
- **Implementation**: `LiveWebEmbedPlayerView` startedPlayback soft-resume; `HybridStreamProvider` descriptor loop keeps collecting embeds; display name `hotel`→Score808; plugin timeout 12s; catalog merge filtered by enabled modules.
- **Verification**: Rebuild app → Watch Now on a live match → confirm StreamEx stays playing after buffer stalls; Change Source lists Score808 when Nexus includes `hotel` and the Score808 module is enabled.

## 2026-08-02: Home iPad hero width from container, not UIScreen
- **Decision**: Hero carousel page width must come from the proposed container (overlay `GeometryReader`), never `UIScreen.main.bounds`.
- **Why**: Screen-width fallback forced the hero wider than constrained columns / Stage Manager windows.
- **Verification**: Built + installed on iPad Air `00008101-001954E20AC0001E`.

## 2026-07-31: Home iPad Spacing — Fill Width, Dense Rows, Capped Dock
- **Decision**: Home iPad layout must fill the hero column (paging ScrollView, not TabView.page), keep vertical module gaps tight (≤10pt), use dense 76pt fixture rows, and center a max-width (~480) tab dock on regular size class.
- **Why**: TabView.page left a dead zone beside the hero; stacked header/date/competition padding created void bands; equal-width full-bleed tabs looked empty on landscape iPad.
- **Implementation**: HeroMatchCarousel + CompactHomeFilterBar + HomeMatchPriority ranking; LiveEventCard densified; MainTabView cinema dock capped/centered.

## 2026-08-24: Matches becomes My Matchday, not a duplicate catalog
- **Decision**: Keep the Matches tab, but make it a personal planning surface. Home discovers every current catalog event; My Matchday contains only explicitly saved matches and fixtures involving followed teams.
- **Why**: A second Live/Upcoming/Results browser duplicated Home and could say “No upcoming fixtures” while Home showed current provider events because the two tabs used different feeds. A persistent tab must earn its place with a distinct job.
- **Implementation**: Home and Matches share `MatchListViewModel.shared`. Home hero and fixture cards expose clearly labeled bookmarks. `MyMatchdayStore` persists bounded event snapshots in UserDefaults; My Matchday groups Live now / Next up / Later / Recent, labels why each event is present, warns when kickoffs overlap, and offers the same honest Watch-or-Details action without routing through Home.
- **Verification**: Catalyst build passed; 30 focused tests passed with one opt-in soak skipped. A Catalyst interaction check proved save → immediate My Matchday row → remove → explanatory empty state → Browse Home. The normal app was signed, installed, and launched on the physical iPhone 15 Pro Max with no UI-test runner; the connected iPad became unavailable to CoreDevice before its install and remains a manual gate.

## 2026-08-24: Slow web sources retry in place; catalog rows represent distinct broadcasts
- **Decision**: Give web embeds 20 seconds to prove decoded startup and reload the same selected broadcast once before automatic failover. Curate real catalog variants across source families, collapse each broadcaster's HD/SD pair to HD, and use viewer counts to rank remaining alternatives. A zero-variant family is omitted when any real variants exist; canonical synthesis is a one-per-family last resort only when the entire event has no variants.
- **Why**: Fulham–Chelsea exposed 18 real Admin variants, one Delta, zero Echo, and one Golf, but Fotty showed Admin #1/#2, Delta #1, two invented Echo rows, and Golf #1. The user could make a source play through repeated manual retries, proving the 10-second failover was too eager, while the picker overstated six meaningful alternatives.
- **Ad containment**: A live WebKit trace showed `embed.st/ad.html` spawning repeated external popup/click-through chains. The player removes that frame and observed nuisance hosts, disables `window.open`, keeps top-level navigation locked, and leaves the video and native web-player controls untouched. Explicit “broadcast unavailable” pages bypass the retry delay.
- **Verification**: Mac Catalyst build passed; the focused playback suite passed 32 checks and skipped only the opt-in soak. A WebKit containment probe produced zero popup pages with one video and one player-control layer preserved. Signed normal build 2396 installed and launched on the physical iPhone 15 Pro Max; final build 2404 installed after the last containment hardening, but CoreDevice could not relaunch it because the phone had locked. No simulator or UI-test helper was used.

## 2026-08-24: Fotty 2.0 is an integrated quality contract, not a feature-count release

- **Decision**: Accept `docs/audit/Fotty-2.0-Benchmark-and-Product-Contract.md` as the implementation and release authority. Fotty 2.0 must complete five connected journeys—discover, watch, deadline plan, live FPL, and review—and pass truth, accessibility, automated, physical-device, and active-provider gates.
- **Why**: Specialist comparisons showed that Fotty's advantage is the connection between matchday and FPL, while its release risk is contradictory or incomplete journeys. A compile or a larger tool list is not a useful definition of done.
- **Boundary**: LiveFPL, FPL Review, FPL.team, FotMob, Sofascore, OneFootball, Apple guidance, and open solvers are behavior/engineering benchmarks. Fotty does not copy unlicensed code, scrape manager totals from a benchmark, fabricate unsupported match data, or promise broadcaster control.

## 2026-08-24: One canonical match identity and one active Match Center

- **Decision**: Preserve a canonical fixture route ID with provider aliases through schedule, catalog, score, FPL context, alerts, Match Center, and playback. Remove the unreachable Dashboard Match Center and obsolete Arena/Highlights Match Hub tabs instead of maintaining a second presentation.
- **Why**: Provider-prefixed IDs and duplicate match surfaces caused score/playback routing ambiguity and dead controls. One identity and one overview make every visible action testable.
- **Verification**: Alias tests cover raw, canonical, and provider-prefixed identities across score/FPL/notification/playback boundaries; the Xcode target compiles with the dead files removed.

## 2026-08-24: FPL truth is deterministic; Coach explains decisions over evidence

- **Decision**: Official current points, legal autosubs, captain fallback, Bench Boost, transfer hits, blanks/doubles, published substitutions, and checked-final boundaries are calculated by versioned Swift and Worker rules. Direct facts/rules use zero model tokens. DeepSeek receives a minimized evidence packet only after consent and must return complete evidence, uncertainty, actions, freshness, source/model, and usage without contradicting verified rules.
- **Why**: A language model confidently denied a valid bench/captain outcome. Current scoring is a rules problem, while strategic choice benefits from an evidence-grounded explanation with explicit tradeoffs.
- **Verification**: Swift and Worker parity suites are green; production Worker `39e913bd-d1fb-48e4-bf56-20be2ba183e4` passed both a fresh zero-token deterministic smoke and a bounded structured model smoke.

## 2026-08-24: Playback evidence is local and retired P2P does not participate in production resolution

- **Decision**: Store only bounded redacted quality outcomes on-device; never add segment-path telemetry. Active resolution uses enabled StreamEx/Score808 catalog descriptors, and the old Hybrid P2P branch is behind undefined `FOTTY_LEGACY_P2P`. A fallback creates one source per family, not invented duplicates.
- **Why**: Playback correctness depends on decoded progress and attempt identity, while extra network diagnostics can harm playback. Retired P2P code and duplicate fallbacks made the supported path harder to reason about.
- **Verification**: Continuity tests cover stale callbacks, network restoration, same-web return after native failure, typed boundaries, and fallback source count. Current near-live browser probes recorded provider-side 403/no-media outcomes without misclassifying them as app playback success.

## 2026-08-25: A loaded web iframe is neither decoded success nor permission to replace the feed

- **Decision**: Direct cross-origin web embeds get a 20-second frame-load window. Once loaded, they stay selected unless the provider reports a concrete error or the user chooses another numbered broadcast; the parent page must not infer decoded success or failure from browser isolation. Same-origin instrumented players may report success only through advancing decoded video. Web Watch exposes no provider new-tab escape and no PiP control without a native video element.
- **Why**: The responsive release audit reproduced a provider frame where Fotty showed PiP/new-tab controls and previously promoted `iframe.onload` to playing. That both overstated capability and enabled automatic source replacement without evidence—the exact continuity failure reported by the user.
- **Verification**: The 390×844 in-app-browser pass kept Broadcast 1 selected beyond the recovery window, exposed no feed new-tab or false PiP control, reported no console error, and presented concise `Broadcast N` accessibility labels. Web/Worker tests pass 68/68 and the production Next/TypeScript build passes.

## 2026-08-25: Match clocks must respect sport semantics

- **Decision**: Fotty estimates a wall-clock-derived minute only for association football. Baseball, basketball, hockey, American football, cricket, and other period/inning sports show `Live` until a provider supplies a trustworthy sport-specific state. Compact glance chips spell out the sport and expose a complete event/timing accessibility label.
- **Why**: The visual release audit displayed `115′` for MLB and reduced `Baseball` to `Bas`, both authoritative-looking but meaningless.
- **Verification**: Four focused clock tests cover football, halftime, non-football sports, stale live flags, and explicit final states; desktop and iPhone-width browser checks show the corrected labels with zero horizontal overflow.

## 2026-08-25: Provider audits must preserve the media request's own referrer

- **Decision**: Apply the catalog/provider referer only to the top-level embed navigation in `audit_live_playback_matrix.mjs`. Never configure it as a browser-context header, because that overwrites the nested HLS request's required `embed.st` referer.
- **Why**: The first release-candidate matrix reported repeated `lb8.strmd.st` HTTP 403 responses. A controlled redacted probe returned HTTP 200 with the embed referrer, revealing that the harness—not the provider—had manufactured the failure.
- **Verification**: The corrected current-catalog rerun decoded advancing 960×540 `golf` video in about 13.8 seconds with media HTTP 200 and zero popups. Three other families remained non-decoding in the bounded window, so source-specific health remains honest rather than generalized from the one success.

## 2026-08-31: Real team labels always carry a truthful badge window

- **Decision**: Treat team identity as one reusable presentation contract across discovery, Match Center, playback, following/onboarding, team news, tactical views, and FPL. `TeamBadgeWindow` resolves explicit artwork, then the shared team-brand cache, then a monogram; `TeamIdentityLabel` binds that badge to an atomic team name. FPL team codes map to the official Premier League crest endpoint. Do not attach a badge to a league, channel, unknown placeholder, custom FPL squad name, or a name embedded only in prose.
- **Why**: Team badges are a distinctive part of Fotty's identity and make dense sport/FPL screens scannable. Older circular images and optional-only `AsyncImage` branches produced inconsistent shapes and blank gaps when a URL was absent or failed.
- **Verification**: Unit coverage checks monograms, blank-name fallback, exact national-team matching, official FPL crest construction, and shared-component presence on representative surfaces. The full no-simulator Catalyst test gate and generic iOS Release build passed with two Xcode jobs; its owned DerivedData was deleted and free disk remained 47 GB.

## 2026-08-31: Build 48 is the shared internal acceptance candidate

- **Decision**: Consolidate the completed badge/motion plan, encrypted private recovery, private build-47 PiP continuity correction and football identity/search work into one normal internal-only TestFlight build. Allocate 48 because Apple showed 46 as the latest upload and direct build 47 was already consumed; never reuse a physically distributed build number.
- **Authority and scope**: The owner explicitly approved continuing through the full six-step plan and then testing, followed by action-time approval for the built-in-encryption declaration, testing notes and only the existing Fotty Internal Smoke group. No new tester/role, external TestFlight/App Store submission, Worker/web deployment, paid model call, simulator, direct install or Git publication is authorized or performed.
- **Verification**: The exact build-48 no-simulator Catalyst unit/generic Release gate, 74 web units, zero-error lint, Worker dry-run, production web build, live three-feed football identity check and same-day 272/272 artwork audit pass. The signed app and Live Activity extension both report 2.0.0 (48), the expected identifiers/team and minimum 26.4; strict signatures pass. Xcode reported upload success at 12:03:54 AST. Apple independently shows build 48 Internal / Testing for Fotty Internal Smoke with two invitations and saved seven-task notes. The iPhone remains build 46 and Jet iPad private build 47 until TestFlight updates; physical acceptance and one received feedback report remain open. The 321 MB archive tree and Xcode distribution logs were removed, returning disk to about 47 GiB free. See `docs/releases/Fotty-2.0.0-48.md`.

## 2026-09-06: Catalog smoothness outranks exact pixel restoration

- **Decision**: Home, Full lineup and Search do not persist absolute lazy-stack
  offsets. Home fixture/date content is flattened so each `ForEach` identity
  resolves to one stable child; presentation data is prepared before row-body
  evaluation, normal row geometry is bounded, and catalog rows share a coarse
  clock rather than creating independent timelines.
- **Why**: Apple documents that unseen lazy geometry is estimated, absolute
  offsets are unstable, dynamic child counts impair lazy-stack lifetime and
  prefetching, and layout changes or repeated work during appearance cause
  missed frame deadlines. Builds 68 and 69 reduced peripheral work but retained
  those structural conditions and were physically rejected.
- **Verification**: The complete no-simulator Catalyst suite and generic
  optimized iOS build pass. Signed build 70 installed/launched only on Jelani's
  iPhone and the app/extension survived the hold. Cold-scroll acceptance remains
  open; no TestFlight/iPad distribution occurred.
