# Fotty 3.0 broadcast-first private candidate

3 November 2026. Owner authorized private iPad and iPhone implementation and
testing. No TestFlight, publication, backend deployment or source opt-in changes.
The [plan](Plan.md) records the approved hierarchy and ordered scope. The later owner instruction to ignore the iPhone stops further phone operations, including final restoration there.

## Implemented

- Single-stream discovery admits fresh, successful match-specific native evidence
  without waiting for the generic grace period. A failed match observation cannot
  borrow success from another match on that host. Remembered wrong-programme
  deliveries are excluded from automatic single-stream selection.
- Sources retain the current player and show station identity where known,
  numbered alternatives otherwise, with provider identity and listed metadata
  secondary. Wrong-match/blocked-picture reporting is visible.
- Home has a larger featured stage with real badges, existing followed-club live
  priority and next-match placement, an optional club-follow invitation, and
  separated live rows. Phone rows reflow Watch below long team identities.
- Sports TV adds local search, All/English/Favourites filters, reset for empty
  results and programme progress only within a verified dated interval. Registry
  refresh uses the existing bounded client cadence. No new sources are enabled.

## Evidence so far

- 113 targeted physical Jet unit tests passed: discovery, source health,
  cancellation/retry, Sports TV, viewing coordinator and Watch feedback.
- Four additional Jet tests passed: three Home selection/ordering checks and the
  native source-sheet render across phone, short accessibility and iPad viewports.
- The production Home → Sports TV → English/Favourites → channel search → empty
  result/reset journey passed on both physical devices before final row polish.
- The signed Release candidate compiled. An earlier unsigned intermediate app
  failed installation; that packaging failure is distinct from app behavior.
- All 42 FPL/multi-stream files in the task baseline remain byte-identical.

## Failed checks kept separate

- iPad complete-string Search replacement still loses characters in XCTest
  (`cricket` observed as `cri` and subsequently `ct`). The separate actual
  software-key test entered all seven characters and settled the correct query.
  The same distinction exists in the build 186 receipt. This is not a proven
  harness-only failure, nor proof of a manual-user typing defect. A stable host
  container did not close this gate; do not claim it did.
- The first phone live-match test repeatedly tapped a More-events row obscured
  by the floating tab bar. The test now reveals controls inside the content
  viewport. That failed run never reached playback and establishes no source
  failure. Its subsequent phone attempt was blocked by device lock.
- Initial iPad screenshots taken with `app.screenshot()` were clipped/oriented
  incorrectly. Full-screen visual acceptance requires the corrected
  `XCUIScreen.main.screenshot()` captures, not those images.

Live acceptance, final normal-app restoration and final visual captures are
recorded below when completed. Passing compile or policy tests alone does not
establish competition coverage, correct programme, sound output or release readiness.

## Startup crash found during device qualification

Both physical devices produced the same main-thread `dispatch_once` recursive-lock
trap in `SportsContinuityBridge.shared`, entered from a second MainTab scene task.
The bridge's singleton constructor eagerly acquired the sync singleton, whose
initializer performed Keychain/iCloud framework work. The new shared store now
finishes construction before that external work; explicit startup rejects
re-entrant callbacks until ready. Bridge configuration, refresh and publication
respect that guard. Consent, journal wire format and FPL boundaries are unchanged.
The [redacted crash receipt](startup-crash-redacted.json) retains the failed runs.
All 57 sync/bridge tests passed, including a writer callback that deliberately
re-enters initialization, refresh and mutation. The source-sheet render also passed
again with the short Sources heading.

## Live single-player evidence

On Jet, ordinary Watch opened the freshly verified New Jersey Devils–Edmonton
Oilers fixture through TV4 on 3 November at approximately 21:42–21:45 Tobago.
Correct programme was visually confirmed: ESPN3, EDM 1–NJ 0, second period.
The 90-second hold advanced 91.63 media seconds on the same native player/item/
attempt. Opening and dismissing Sources preserved that owner. Actual mini-player
Pause stopped the clock; Play resumed on the same owner. This run did not inject
an outage or claim audible sound. The earlier 228 TV4→CS4 forced recovery remains
a separate dated receipt; no new PL/UCL coverage claim follows from this NHL check.

## Final private Jet result

Normal signed Release **3.0.0 (229)** is installed and launched without test
arguments on Jet. Its binary hash and detailed boundaries are in
[acceptance.json](acceptance.json). After the startup repair, repeated native
launches plus light/dark Home checks passed. The final Release Watch/mini-player
Pause/Play check passed on the same TV4 player/item/attempt; its pictures were an
ESPN3 break/bumper, so it does not replace the earlier actual-game 90-second hold.
Ten protected Jet preference keys and 42 excluded source files matched their
pre-task values. No current settings or source grants were reset.

The 174 distinct targeted unit checks passed (175 executions including the
repeated source-sheet render). This is **private candidate acceptance, not a claim
that every gate passed**. Rapid complete-string Search remains unresolved. Final
phone testing/restoration was stopped at the owner's explicit instruction; the
phone does not contain the final startup repair. No TestFlight or cloud changes.

### Visual comparison

- [Jet dark Home](evidence/jet-home-dark.png) and [light Home](evidence/jet-home-light.png):
  featured live stage occupies the primary column, next fixtures use the second
  column, clear boundaries and real badges remain. The existing refresh failure
  notice is still visible; this pass does not conceal or resolve provider health.
- [Sports TV](evidence/jet-sports-tv.png): native search and compact filters,
  English station selection and preserved Now/Next evidence.
- [Player](evidence/jet-live-tv4.png) and [Sources](evidence/jet-sources.png): video
  remains dominant; the source sheet presents alternatives without remounting it.
- [Short accessibility Sources](evidence/source-sheet-short-accessibility.png):
  title and dismissal fit; choices remain scrollable below the summary/filter.
  This is a bounded component render, not a physical phone pass.

No pixel baselines were promoted. Capture provenance/hashes are in
[visual-evidence.json](visual-evidence.json). Phone long-name reflow is source-checked
but final physical phone acceptance remains open under the owner's stop.

Prior acceptance references: [226 match recovery](../fotty226-match-recovery/live.json), [225 Sky Cricket](../fotty225-stations/qualification.json), [224 FS1/Sky Main](../fotty224-channel-recovery/qualification.json); 222 tailored Home is reused.

## 3 November — Search follow-up after phone stop

Source inspection found one scene-scoped query owner. Result/index tasks publish
snapshots, not query text; explicit shortcuts and the 120-character limit are the
only app-side query assignments outside the native binding. No duplicate writer
or stale-result overwrite of the text was established. Scene restoration, native
focus/keyboard transitions and XCTest delivery remain hypotheses, not diagnoses.
Apple's [SceneStorage contract](https://developer.apple.com/documentation/swiftui/scenestorage)
does not by itself establish a defect in using this binding. The installed
XCUIAutomation header requires keyboard focus for `typeText`; keyboard visibility
alone is not proof of the entire input-delivery path.

Added `testPhysicalSearchClearRetypeAndReopenPreservesExactInput` to isolate Search
from unrelated Matchday navigation and check complete football/cricket/empty-result
queries across native Clear and sheet reopening. It retains exact-text assertions
and uses no suffix repair, paste, synthetic query assignment or production hook.
Swift syntax parsing and diff checks passed. **The new test has not run on Jet.**
Device Hub's Jet preview was black and then disconnected; a wake/free-device
request is pending. No build, install, app launch, query mutation or phone operation
was performed in this follow-up. Normal Jet 229 remains the last verified installed
build. Production Search is unchanged; the rapid-input gate remains open.

## 3 November — Search repair verified on Jet230

The later connected-device check supersedes the unavailable-preview state above.
A black Device Hub preview did not establish that Jet was asleep. On normal229,
one captured-keyboard input of `football` retained `Foot`; `cricket` retained
`Cric`. Sports TV retained all of `Cricket` through the same input path. This
establishes a global-Search input failure, not an internal framework diagnosis.

The focused repair gives the native Search field a local editing state and keeps
SceneStorage as a checkpoint at dismissal, submission and scene inactivity. It
restores once on presentation. Result/index tasks, matching and stream code are
unchanged. Signed Release230 compiled and its deep signature verified. The
existing Release unit-test build configuration lacks enable-testing; an owned
temporary UI-only scheme reused the compiled app. No fresh unit-test pass is
claimed in this follow-up.

The first two physical tests failed at the software-keyboard precondition while
Device Hub was attached, before typing. They remain failed receipts. The same
compiled tests passed after quitting Device Hub: **2 passed, 0 failed, 0 skipped**
in92.520s. No assertion weakening, suffix repair, paste or query injection. The
gates cover real software keys and complete `football`, `cricket`, `zz`, `cricket`
inputs, native Clear, current results and exact restoration after sheet reopening.
Manual captured-keyboard input also retained complete football/cricket and
reopened cricket.

Normal230 launched without test arguments; Search was blank after that launch,
recent history and11 protected preferences unchanged;42 excluded FPL/multi source
hashes unchanged. Phone untouched. The existing refresh warning still appears;
this Search fix does not qualify provider recovery or new PL/UCL streams.
See [redacted230 receipt](search230-acceptance.json).
