# Phone177 — private native UI review,25October2026

The owner separately requested installing the UI candidate on Jelani's iPhone
and testing it. This ends the old175 hold for this UI gate only; source campaigns
remain metadata-only. Jet was not operated. FPL/multi-stream source and settings
were not edited, and no TestFlight/Git/cloud publication occurred.

## Exact candidate and native evidence

- Normal signed Release2.0.1(177), built with Xcode27.1(27A9275), installed in place
  on the freshly identified iPhone15ProMax/iOS27.0.1. App and extension both177;
  strict/deep signature verification, installed-app readback and argument-free
  launch pass. The pre-existing phone app was175.
- All310 declared application/test/project inputs match before and after the
  gate. Input-list SHA256:
  `cf38bb7e576c9c09885c7707bdebb5cc210eae2c6fff34ed71ad5bde633d6e33`.
  The unchanged57-input UI ledger digest remains
  `d411c01a6cf17b9cc07b950ead476eb2c6625964cf7a21841f2ed5f7f5f72a2c`.
- Normal Release executable SHA256:
  `b0960af98dc2ddd5005ddcfe8f88631c8948b08f5e3c81e55780ec07f943f54a`.
  This fresh27.1 binary is not the earlier Jet27.0 executable despite sharing177.
- These four PNGs are Device Hub's native phone Screenshot exports,1125×2436,
  from normal Release177 after restoration, not a browser, Catalyst or a test
  fixture. They retain actual content/owner text size and dark appearance, not
  a deterministic clock, universal phone viewport or reviewed golden baseline.

| Capture | Observation | SHA256 |
| --- | --- | --- |
| [Home](phone177-home.png) | Lead match, readable crests/identities, grouped rows and native glass tabs. | `26bb31bb0abd79e1da789c3d3994d9dca289eb91b440269d107298faf0fa0809` |
| [Matchday](phone177-matchday.png) | Normal saved/followed data, sections and visible Watch; no save/remove actions. | `49f7d92e86dba8ac05c474cfbe31cd25a2b2a56b48c194a33ef4bcaf62f8b8c0` |
| [Search/keyboard](phone177-search-keyboard.png) | Actual software-keyboard typing and results; input/clear/cancel remain above it. | `5b5ea10b16eaaef2493d0887f6549eea781de1f205bf383fa91383c97b6fdfb4` |
| [Home sports](phone177-sports-grid.png) | Three equal-size columns, real sport artwork and wrapped American football label. | `db44ca633368c24e640baf734b4bc4713621b2177f4267b164393b385381245c` |

## What actually ran

Manual Device Hub taps/dragging on normal177 verified Settings→Appearance→back,
Matchday→Home, Search focus, transient `Cricket` typing/results, clear/cancel and
Done. The query was not submitted or added to Recents. Home scrolling and native
tab collapse/expansion were observed. Match details opened at the medium sheet;
the requested large-detent/Close sequence was not established by the subsequent
remote gesture. Do not promote it to a full details journey pass.

The default-text Search prompt still shows a taller American football tile than
the adjacent one-line sport tiles. The Home grid is equal-size. This is a concrete
minor Search consistency follow-up, not an installation failure; no new UI design
or source policy was changed during this deployment-only gate. Duplicate-looking
provider/official aliases in Home are only a visual observation here, not a
verified identity/fixture diagnosis or permission for a backend repair.

The focused Debug177 test build passed compilation, but **zero requested phone
UI cases executed**: iOS's Enable UI Automation passcode approval timed out during
runner initialization. The result bundle records one infrastructure failure,
not a failing app assertion. The blocked session and its automatic diagnostic
collector were stopped without entering a password. No XCTest pass, decoded
playback, fullscreen/PiP, accessibility or performance qualification is claimed.
The earlier392 Catalyst/four Jet results remain separate historical evidence.

Normal signed Release177 was reinstalled and launched without test arguments or
environment. After manual checks the owner was visibly using another app/playing
a video, so control stopped. The owner then explicitly requested leaving the
phone alone; do not resume device work without a new owner request.
Phone player/source-sheet interaction and actual
VoiceOver/large-text/performance checks remain open. The source campaign's
programme/90-second/normal-picker gates remain separately pending.

## Preservation and cleanup

The phone's own binary-plist snapshots compare equal for all12 present protected
configuration keys, including absent-vs-present entries, manager connection/
confirmation, the complete plugin-state dictionary, sport IDs, existing saved
matches, appearance and search history. This does not assert byte identity of
derived caches or semantic preservation of every SwiftData row. No Jet settings
were copied to the phone; no source was enabled for a screenshot.

The runner was absent before this gate; the newly installed runner was removed
and absence verified. One owned temporary build directory and keep-awake process
were used; no simulator or concurrent heavy build. Private preferences, build
products, interrupted test results and automatic diagnostics are temporary and
were cleaned at gate exit. Only these small native exports, redacted receipt
and310-file source-hash list are retained.

Final closeout: preservation and all310 source checks pass; installed-app readback
is177. The owned988,256KiB temporary gate and scoped keep-awake process are gone,
with absence verified. Free disk is about64GiB before and56GiB after; the entire
Mac's change is not attributed to the owned output. No unrelated cache, system VM
file, artifact or user data was removed. The phone was left in the owner's app,
not taken back to Fotty for a final screenshot.
