# Nine-fix private Jet verification — 25 October 2026

The [nine approved repairs](../../audit/Fotty-Nine-Core-Fixes-2026-10-25.md)
are installed as normal signed Release **2.0.1(178)** on Jet iPad. The phone
was not operated or updated. FPL and multi-stream remain unchanged; no Git,
cloud or TestFlight publication occurred.

[verification.json](verification.json) retains redacted test counts, executable
identities and scope. The native regression gate covered 363 unique selected
cases: 362 initially passed; one obsolete quarantine assertion was corrected,
then all 40 affected rerun cases passed. Those counts overlap. Eleven web
catalog tests and generated-catalog coherence pass. Physical XCTest executed
zero requested cases because enabling automation timed out at the Touch ID
gate; this is not an automated device-suite pass. The normal app was tested
directly through Device Hub instead, and the temporary test runner was removed.

## Actual iPad observations

[manual-journey.json](manual-journey.json) records the bounded normal-app journey:
Home, Search, Settings, local Darts selection/restoration, empty Matchday recovery,
catalog details and portrait/landscape composition. The actual Search tile
surfaces align, including American football; the original query was restored
without submitting or changing recent searches. Hosted component captures also
exercise narrow, ordinary and accessibility-layout geometry. They are not a
physical iPhone or accessibility certification.

The existing Willow channel visibly decoded changing cricket footage through
the unchanged Broadcast1 route. Sources remained usable and retained the selected
delivery. Existing native-player handoff and fullscreen worked. Native pause,
inline return, minimize, reopening the same Watch and resume retained the paused
frame without a visible Connecting/discovery screen. Native PiP rendered changing
programme outside Fotty on iPad Home; returning and restoring native fullscreen
retained the paused image after a deliberate control interaction, and Play
resumed advancing programme. Closing fullscreen returned to inline Playing.

This is existing-channel transport/control evidence, not verification of a
currently live fixture, source completeness, a new provider, audible output,
lock/unlock recovery, physical Dynamic Type or VoiceOver. No new stream source
was enabled or qualified. The test stream was stopped; Jet was left on Home,
All sports, portrait, with no PiP/dock and keyboard capture off.

## Preservation and evidence

[preference-preservation.json](preference-preservation.json) confirms exact
before/after equality of 23 configuration slots, including absent/present state,
six FPL slots, source enablement, saved-match plist and sync consent. Sports sync
stayed off. This does not certify every SwiftData row; destructive/quota failures
were tested in isolated stores, not the owner's data. All 59 protected source
hashes matched the prior baseline. The 313-input manifest is retained in
[app-inputs.sha256](app-inputs.sha256); inputs were unchanged after final build.

The [current UI ledger](../../design/fotty25-ui-reference-contract.json) binds
fresh captures to the 57 focused dependencies. Earlier177 captures are explicitly
historical, with their original provenance retained in
[historical-177-evidence-contract.json](historical-177-evidence-contract.json).
The [integrity report](ui-evidence-check.json) is not release acceptance or a
complete whole-app visual gate. Original golden baselines are unchanged.

All PNGs here are original native exports or native hosted component output;
they were not resized or edited. Native landscape images are 2360 pixels wide,
above the existing bounded ledger's 2000-pixel width limit, so their identities
are retained separately in [native-landscape-evidence.json](native-landscape-evidence.json).
[Native fullscreen](jet178-native-fullscreen-release.png) is also retained
separately at its original resolution (7.6 MB, above the ledger's 2 MiB image
limit). Validator limits were not weakened. The exported inline source-picker
PNG omits its video surface; decoded moving frames were observed in Device Hub.

The owned temporary build/results/preferences gate and keep-awake process are
removed after retaining these redacted receipts. Raw device preferences,
diagnostic bundles, signed apps, media URLs and private identifiers are not
retained in this pack. Cleanup result is recorded in verification.json.
