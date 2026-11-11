# Fotty 2.0.1 (142) — retained viewing experience, private Jet gate

13 October 2026. The implemented milestone is now signed and installed only on
Jet iPad (Air4, iPadOS27.0.1), with exact2.0.1(142) readback. Owner phones125 and
shared TestFlight121 are unchanged. No backend deployment, Git publication or
TestFlight action. Physical qualification is bounded below, not a blanket pass.

## Approved scope and implementation

The owner approved the full-experience concept for iPhone/iPad, followed by
private Jet iPad testing. FPL must stay unchanged. Sports-only iCloud and widget
capabilities are approved, but sync is off until explicit opt-in.

- Persistent scene-owned viewing; native compact tab accessory while browsing.
  Full/compact/Focus/Watch Two retain media owner, item/source/attempt and pause.
- iPad companion and independent pane Sources/Audio/Keep controls. Focus fits
  short windows; narrow/accessibility layouts reflow. No ambiguous global
  compact Pause for two panes. Actual PiP claims select the sole audio owner.
- Personal Tonight 90-minute/two-hour/local-evening plan, separate from Home
  discovery and Full Matchday. Common terminal/conflict policy stays authoritative.
- Explicit expiring Handoff, fresh receiving identity confirmation and source
  lookup; no device picker, acknowledgment or automatic sender stop is promised.
- Opt-in sports-only KVS intent sync and signed App Group sports-plan widget.
  No FPL, source URLs/headers/cookies, viewing history or reminder consent sync.
  Durable verified application receipts survive relaunch; failed saves and
  unavailable fixtures cannot create destructive echo or invented plans.
- Quiet decorative football Home backdrop from existing bundled art. No badges,
  sports equipment artwork, provider trust settings or feed contracts replaced.

Native adaptation: companion data is limited to actual available football
score/status/timeline and verified schedule/status elsewhere. No fake cricket
scores, overs, lineups or stats. WidgetKit owns refresh timing; expired status
loses authority even if a new timeline is delayed.

## Local verification

- Final complete Catalyst suite: 1,266 tests, 1,264 passed, two existing optional
  skips, zero failures. Includes 22 coordinator, 12 playback ownership, eight
  scene lease, 10 viewing-plan and the continuity/widget/monitor regressions.
- Initial six sync-test crashes were isolated to a missing strong lifetime for
  the in-memory test ModelContainer. The fixture now retains it. No production
  change was made to disguise that test crash.
- The two new Web PiP test failures used a fake `.m3u8` URL that correctly
  classified as native. Corrected only the fake embed route, added explicit
  mode/callback assertions and retained all strict ownership/pause assertions.
- Ten pinned Catalyst component PNGs manually inspected. Only the five intended
  Home decorations change; both source layouts, controls and badge fixtures are
  byte-identical. Non-recording visual comparison passes. This is not mobile UI.
- 32 source-membership tool regressions pass. Explicit target inventories:
  app 183, tests 53, UI tests 4, extension 5. Versions agree at 2.0.1 (142); plist,
  provider identity and catalog-generation checks pass.
- All 42 FPL Swift source hashes match the starting state. Existing uncommitted
  FPL work from earlier tasks is preserved, not attributed to this milestone.
- Current-source native app/extension and unsigned iOS UI-test compilation pass.
  A temporary UI-only Release scheme retains the normal release product; the
  normal scheme's unit targets require testability and are qualified separately
  by Catalyst. The temporary scheme was removed by its cleanup trap. No simulator
  or parallel heavy build was used.

The final signed-build source recovery receipt is
`backups/release-source/2.0.1-142-jet-complete/receipt.json`:
commit`62a2ce5f8f7ee0bef2a1583c928d95fcf932c065`,
sourceSHA256`4e73342459bf0215e649b3b0e5941d1a18c1ed9bdf45e8378b953a2c18a7651a`.
All1101 source files were verified before build and compared before install.
It is an ignored history-free local recovery bundle, not a Git publication.
Later acceptance documentation/memory exports are not binary inputs.

## Signing and focused native corrections

The owner signed into Xcode. App/extension provisioning now admits the approved
`group.com.jelani.Fotty.sports`; the app also has the sports KVS entitlement.
Strict deep signature validation passes. A read-only device copy confirms the
shared preferences contain only the sports snapshot key, currently an empty
saved plan. Sync remains off in the actual Settings UI; no owner cloud opt-in or
account data was changed to obtain a passing test.

Physical checks exposed small, focused presentation defects:

- Explicit containment groups prevent parent identifiers from overwriting
  Minimize/Close, companion, Tonight-duration and retained-surface controls.
- The always-mounted foreground region is modal while expanded, with lookup
  Cancel inside it; the background is inaccessible/noninteractive then. The
  retained pane ForEach never moves between structural parents.
- Warm sports-plan/Matchday links minimize the existing player before showing
  Matchday. Pause/item ownership is retained; the FPL route is unchanged.
- Small sports widgets use one whole-widget URL; larger families keep row Links.
  The existing FPL widget is unchanged.

An initial raw-XCTest assertion that `home-search.exists == false` was invalid:
hierarchy membership is not VoiceOver focus traversal. It was replaced by actual
blocked-touch/foreground-control checks, not a weaker VoiceOver passing claim.
Search automation now clears/reacquires the real field and submits one complete
query; it never repairs a suffix or alters production Search.

## Physical qualification and remaining gates

Final exact-source seven-test run: **five passed, one failed, one skipped**;
overall XCTest result is Failed, not green. Pass durations: Search49.565s,
Home boundaries/light-dark28.373s, sync-off16.280s, Tonight/Full25.199s,
retained viewing/warm URLs108.610s. The retained journey used the Web route:
canonical pause/Focus/touch/Stop passed, but no native identity receipt existed.

The widget test failed at180s before reaching Edit Home Screen/gallery: public
SpringBoard Dock/Options actions each consumed60s waiting for a missing system
animation-complete notification, with remote AX-server errors. No empty-widget
assertion ran. This is unavailable system automation evidence, not a confirmed
Fotty widget defect or a rendering pass. No private idle override, forced tap,
longer allowance or product workaround was used to hide it; no widget was added.

Watch Two skipped at242.901s. Pane1's requested source and the prior healthy
sibling each acquired exact Try again/distinct-fallback receipts; pane2's
alternate row selection qualified. Menus, sole audio selection, Swap, Return and
Stop were exercised; neither pane supplied native identity. This does not prove
the switch caused the sibling recovery or qualify two alternate decoded pictures.

Earlier corrected Jet runs pass real Home light/dark separation, complete Search,
Tonight/Full mode, sync-off disclosure, retained full→compact→tabs→full with
explicit pause, portrait/landscape Focus, Sources and Stop. A prior Watch Two run
passes both pane menus/alternate selection, sole selected audio owner, Swap and
Return to one. Later source attempts require fallback and remain unqualified;
selected rows and muted UI tests do not prove two decoded pictures/audible audio.

Real60s native PiP in142 skipped because no ready native layer/progress/PiP hook
was available. The141 CS6/timstreams same-item PiP pause is still unresolved,
not fixed or erased by this presentation milestone. Actual VoiceOver traversal,
large text, Details-cover/scene-disconnect hardware behavior, populated widget
timeline/link/expiry and real iCloud initial-sync/account behavior remain open.
Cross-device Handoff/sync and exact phone visual acceptance need separately
authorized current signed devices. No older phone/Mac app qualifies142.

The final four light/dark/top/scrolled attachments were inspected. Their
orientation metadata renders misleading crops in the local image viewer; a
fresh normal-build Device Hub landscape view confirms the actual1180x820 Home
fits, has separated cards, real artwork and six sports per row. Do not alter
layout to compensate for rotated attachments. The owned UI-test runner is removed
after testing; the ordinary signed app remains for the owner. Its normal launch
was visually inspected and the same process remained present beyond30 seconds.

| Surface | Intended relationship | Available evidence / remaining gate |
| --- | --- | --- |
| Home | Real crests, calm hero, restrained artwork | Actual Jet wide light/dark/separation and Search pass; phone/large text open. |
| Tonight | Personal anchored plan, distinct from discovery | Policy and actual Tonight/Full controls pass; no saved-plan writes during tests. |
| Single/compact viewing | One media owner across tabs and return | Native controls, pause, Focus, browse/return and Stop pass; absent Web identity is unknown. |
| iPad companion/Watch Two | Useful side column; independent sources/audio | Actual geometry and selection/Swap controls checked; two decoded/audible outputs not qualified. |
| Continuity/widget | Explicit sports-only transfer and expiring snapshot | Signed App Group write and sync-off verified; real cross-device/timeline gates remain. |

## 13 October: Phone/cross-device gate deferred by owner

The owner subsequently said to ignore phone testing for now. Phone installation,
connection repair and cross-device testing are deferred; the Mac pairing window
is cancelled. No phone was installed/tested and no cloud toggle was changed.

The owner approved installation on Jelani's iPhone and actual phone/cross-device
checks, plus temporary sports-only iCloud opt-in followed by sync-off cleanup.
FPL and TestFlight remain excluded. No cloud toggle was changed in this attempt.

The matching signed Release/UI-test build compiles and passes strict signature
and source comparison.212 native build inputs match the installed Jet source;
all42 FPL source hashes remain unchanged. Local pre-build recovery receipt:
`backups/release-source/2.0.1-142-phone-cross-device/receipt.json`,
commit`cfc8b98eb5beeaf422df7ac90795db5207372fbc`,
sourceSHA256`4f9c5fa1322b699ae202f5398ceccc6762aad03f54d79aa5a7fa0c41079ac866`.
This is build provenance, not phone installation or cross-device acceptance.

Fresh CoreDevice, xcdevice, USB and Bonjour checks find Jet only; the historical
Jelani phone identity is absent, not a selectable unavailable target. No tester
phone is substituted. Device Hub was running from beta Xcode; it was closed and
reopened from the stable build toolchain. Apple's Pair Nearby Device route is
open, but still says Waiting to pair and requires the phone's Developer Mode
page/normal pairing request. The mismatch is not a proven root cause. No pairing
records, network/privacy settings or device data were reset; no daemon was killed.

The bounded continuity review also confirms an API-contract gap: initial KVS
loading is not a guaranteed completion notification. Empty/unchanged first-use
can wait indefinitely because142 forbids writes until an external notification.
No actual phone/cloud reproduction or safe production repair is claimed. This
must be resolved/qualified before calling sports sync functional; do not inject
a fake initial receipt, delete accepted journals or treat queued as delivered.
See the13October entry in Risks. Temporary compilation/discovery outputs and
keep-awake are cleaned while the on-device pairing step is outstanding.
