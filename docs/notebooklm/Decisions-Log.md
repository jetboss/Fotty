# Fotty Decisions Log

## 2026-08-30: Treat active native PiP as background playback, not foreground decoration

- **Finding**: On a real iPad, native handoff entered the system PiP window but playback paused as soon as another app opened. Fotty declared the audio background mode and retained its PiP controller, but set only the audio-session category, left `AVPlayer.audiovisualBackgroundPlaybackPolicy` on `.automatic`, and incorrectly marked an active PiP session for foreground resume.
- **Decision/implementation**: Activate the `.playback`/`.moviePlayback` audio session only when playback or PiP actually begins, set every direct and web-handoff native player to `.continuesIfPossible`, reassert both at the PiP/background boundary, and keep the active native state without arming foreground recovery. A stopped/failed PiP while backgrounded still pauses safely. The controller now acknowledges restoration to the still-mounted player UI.
- **Evidence/boundaries**: Add a unit regression proving active PiP remains `.playing(.native)`, retains its background policy and does not mark itself for resume after backgrounding. The full Catalyst suite and unsigned generic iOS Release pass without a simulator. This cannot prove iOS process scheduling, a header-proxy stream or system PiP controls; repeat on the physical iPad by opening another app and locking/unlocking. No device install, TestFlight upload, stream request or version bump.

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
