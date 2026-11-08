# Fotty 2.0.1 (171): video-first single-player on iPad

24 October 2026. Private Jet iPad only. FPL, multi-stream, phones, source
admission/defaults, backend, Git publication and shared TestFlight unchanged.

## Delivered

- iPad single-player now gives the video the largest uncropped 16:9 fit in the
  available stage. No permanent match-detail sidebar or width-threshold rail.
- Compact badge/title header; Sources and Details in a dock outside media bounds.
  Details is a dismissible native sheet. Narrow/short/accessibility layouts use
  labeled accessible symbols, with complete match identity in Details.
- The scene's existing retained media owner stays mounted. Moving/rotating the
  layout or opening/closing these sheets does not resolve or restart a source.
  Explicitly choosing a different source still connects to that source; this is
  not a promise of gapless switching between unrelated deliveries.
- The existing same-player/item native fullscreen action and Apple controls are
  retained. Provider/WebKit controls and the phone/two-player paths are unchanged.
- Apple UI guidance informed the adaptive fit, native sheet, touch separation
  and preservation of native playback controls; no interactive media overlay was
  added. This is source implementation, not a claim of completed Stremio REA.

## Verification actually completed

- Nine new pure layout tests in the existing test file. Focused Catalyst gate:
  **62 passed, zero failed/skipped**, no runtime warnings. Includes native
  fullscreen ownership and retained minimize/reopen model tests. Catalyst unit
  evidence is not physical iPad playback evidence; no simulator was used.
- Native source membership and app/extension/source Debug/Release versions pass.
  Normal signed Release app and extension both171; strict deep signature passes.
- Physical transport-independent presentation test: **one passed, zero failed/
  skipped**, 57.175s, on Jet iPad Air4 / iPadOS27.0.1. Normal real Home Watch,
  portrait/landscape/original orientation, Details/Done, Sources open/cancel/
  reopen, selected-source invariant and Close were exercised. No injected
  fixture, Search fallback, source enablement, account or synthetic media.
- Actual screenshots show the Villa–City TNT programme (sampled88:40/88:43),
  not just loading copy. Landscape AX records a1180×820 window and video slot
  at31,88 sized1118×629; dock at362.5,727 sized455.5×58, outside the video.
  Exported landscape PNG has orientation metadata; do not treat its rotated
  preview alone as a pixel-perfect native-frame or continuity measurement.
- Normal Release171 reinstalled, version read back and launched without the
  physical-test environment; device left on Home. The UI runner, absent before
  this gate, was uninstalled and absence confirmed.
- All45 protected FPL/multi-stream hashes, four private FPL/manager/coach values
  and all five existing source-enable states match baseline. AS stays OFF;
  Jet's previously enabled LS remains ON. No private preference values retained.

## Initial remaining gate — superseded by follow-up below

The initial **physical AVKit Pause/Play/fullscreen-return ownership test was OPEN**.
Its real Home source was Web-based. At most two real alternatives were sampled;
neither produced ready, advancing native video within the bounded setup. The
test correctly skipped (0pass/1skip/0failure,118.773s). This does not establish a
provider-wide failure or qualify native controls from a Web screenshot. Existing
native implementation and62 local checks pass, but they do not close this gate.
No PiP, audible-output, sustained decoder soak, large-text device or phone claim.

Two earlier UI attempts failed harness-only selectors (inherited hero More ID,
then a merged container ID); both corrected without changing the player. Another
attempt skipped because live metadata changed the exact FC spelling of a test
filter; the final presentation gate filters the observed real Home control.
The app's Release unit-test target is not testable; a temporary UI-only scheme
avoided changing production testability. That scheme was removed. Existing
compile concurrency/deprecation warnings are not claimed fixed by this UI work.

The separate AS football/cricket source campaign is still pending normal-picker
qualification/additional cricket. Build170's decoder result remains narrower
than that campaign's end-to-end gates; see release170 and the dated source audit.

## Installed-source receipt and resources

1138 source inputs captured before the final normal build and compared before
and after installation, before documentation closeout. Test-harness edits did
not change production playback after the62-test local gate.

- Label: `2.0.1-171-private-video-first`.
- Temporary history-free snapshot commit: `7c5007f6e96b463c5d5635e73838a337cc3bc402`.
- Source SHA256: `7c57087dac7c1d2516af357b7c4a5cade48c15c693aa08cb14353a2cbf7f6b5d`.
- Bundle SHA256: `91cafdf9f997e722b6ee82823fa00c54d8caa20ec6ee0dc124f96f151c326615`.
- Installed signed executable SHA256: `15106d3a841d215dcaa73f61d970bfa3b0736b27c3c7edfed041f2aded23cea2`.

The owned DerivedData/snapshots/preferences/screenshots/logs/results gate (~1GB)
and temporary test scheme were removed; this task's awake helper was stopped.
Free disk returned from19GiB to20GiB. Unrelated files/caches were preserved.

## Native fullscreen follow-up — 24 October, completed on Jet

The owner requested completion of the remaining native gate, preserving the new
layout and leaving FPL/multi-stream/phones/TestFlight alone. No production player,
renderer, source adapter, admission/default, audio or layout code needed repair.
Version remains2.0.1(171); the changes are focused physical-test coverage and records.

### Correct the gate, not correct playback code

The earlier setup sampled only two visible alternatives for25s each. It could
miss a native option lower in the picker and undercut legitimate preparation plus
the existing30s LS startup policy. A new focused test selects a bounded public
label from the real existing Home match picker, scrolls normally and allows60s
for preparation. It requires the requested row to remain selected/nonfailed and
Native, plus ready displayed video and advancing time. No fixture/media injection,
reference video, source enablement or fallback substitution can qualify it.

CS6 on the real Rayo Vallecano–Elche Home row supplied native1280×720 playback.
The first attempt passed Pause, paused Done/re-entry and Play but failed its last
Close command: the test traversed AX again between finding and tapping AVKit's
button. The failure hierarchy still held the Video/measurement while buttons had
auto-hidden; same-owner ready/rate1 evidence preceded it. Remove that redundant
traversal and generic tap polling, tap the actual exposed system control directly,
and collect broad diagnostics only on failure. Ownership/rate admission and all
post-action invariants remain required. No fake control, forced tap, swallowed
failure, AVKit auto-hide override or production fix was introduced.

### Fresh physical results

- Portrait: **1passed,0failed/0skipped**,67.199s.
- Landscape: **1passed,0failed/0skipped**,76.181s. Device Hub rotation and real
  wide app windows were verified; original portrait orientation restored afterward.
- Each independent real-source run exercised two actual AVKit presentations:
  Apple Pause/stable paused clock → Done/paused inline → re-entry still paused →
  Apple Play/ready advancing video → Done/ready advancing inline → Sources reopen/
  dismissal with the same selected CS6 row, then normal Close.
- Portrait yielded20 valid native receipts and landscape21. Within each run,
  exactly one player, one item and one attempt UUID persisted. Portrait's paused
  clock stayed17.590s through return/re-entry, then advanced to28.167s after source
  controls; landscape stayed16.045s while paused, then advanced to30.012s. These
  are separate fresh runs, not one owner across test launches.
- Actual native screenshots show the RAY0–3ELC programme at sampled73:02/73:04
  and82:03/82:15. This closes native presentation/control/retention acceptance for
  this sampled delivery, not independent source supply, full-league uptime, PiP,
  audible output or a sustained pixel-buffer soak. No AS/cricket promotion.
- Normal signed Release171 restored/reinstalled/read back/launched without test
  environment. Strict deep signature and target/version checks pass. All46
  protected FPL/multi-stream/new-layout hashes, four private FPL values and all
  five enable states unchanged (AS OFF, existing Jet LS ON). UI runner removed.

Apple's current [native-control documentation](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/showsplaybackcontrols)
supports leaving the system controls intact. The Apple UI skill constrained this
gate to native interactions and actual-device evidence, not another visual redesign.

### Follow-up normal-build provenance

1139 inputs captured before the final normal build and compared before/after
installation, before documentation closeout. No real Git refs/index/remotes changed.

- Label: `2.0.1-171-native-fullscreen-acceptance`.
- Temporary snapshot commit: `070f62086c3533bef15df8d9587fa388d174f6a0`.
- Source SHA256: `bf34a11e18b7fd6680839555cc20d6f1c1fe50a8dbf11c6222a9e9f4502f190d`.
- Bundle SHA256: `b851af33a4f17785442c6a1233e565d54621b9ee34fc33a1c8e6c00070a067ea`.
- Normal signed executable SHA256: `bb21c9e45467221a404ef086f61fa0f90c0fbe1efb10396a96cf52a1b475d6fd`.

The646MiB owned gate and temporary scheme were removed, its awake helper stopped,
and free disk returned from19GiB to20GiB. Only redacted receipts remain; unrelated
files/caches were preserved.
