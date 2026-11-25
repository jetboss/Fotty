# Private Jet installation and live-source gate — 28 October 2026

## Outcome

Normal signed Release **2.0.1(183)** is installed and launched on Jet iPad.
This is **not a completed live-playback qualification**. The normal app's real
existing-match lookup was exercised, but no admitted current delivery reached
the player in this window. There is no new decoded-frame,90second programme,
fullscreen, Pause/Play, source-switch or PiP pass for183.

Phone177, FPL, multi-stream and shared TestFlight121 were left alone. No Git
publication, backend deployment, source-default change or admission expansion
occurred. All seven previously enabled private source providers remain enabled.

## Focused repairs and verification

- **AS catalog routing:** manifest1.9.82 advertises the reviewed
  `plaviohd-football` catalog. The legacy live-sports catalog currently carries
  generic channels. The adapter selects the unique advertised football catalog,
  keys its cache/generation to that selection, and revalidates the same catalog.
  Legacy manifests retain their old route. No extra parallel scan or wider
  manifest/date/stream admission was added. Seven offline regressions cover the
  routing change. The compiled AS run passed67tests, failed0, skipped1explicit
  physical-only gate; a skip is not playback evidence.
- **CNC exact team names:** the current provider says `Capitals vs Flyers`, while
  the NHL fixture says Washington Capitals versus Philadelphia Flyers. Two exact
  source-local aliases repair this corroborated join. Extended/squad names,
  conflicting IDs, wrong dates and wrong leagues remain rejected. Four new
  regressions cover the observed join and the real adapter path. The compiled
  CNC/optional-lookup run passed46tests with0failures/0skips. These are separate
  runs, not an additional unique combined-test count.
- Both signed Release builds182and183 passed. Strict deep signature, device
  provisioning and installed version readback passed. Every one of the34existing
  preference slots matched before launch after each in-place installation.
  Final personal/source settings match19of19 selected slots; the five changed
  runtime slots are not a claim that every runtime cache is immutable.
- All314 exact final build inputs match the workspace and compiled snapshot.
  All43 protected FPL/multi-stream source hashes match their starting hashes.
  The local signed executable hash is retained separately from installed-version
  proof; a device-side executable hash was not measured.

An initial hypothesis about a hockey catalog eligibility guard was disproved
by its focused tests. That speculative change and its tests were fully reverted;
the original production guard remains. Its failed experimental assertions are
not represented as failures of the final retained candidate. Match details did
contain Check streams; in landscape it was below the sheet's visible fold.
Portrait made it reachable without changing the interface.

## Real normal-app source check

The additional fixture was used only to exercise the normal source check and
potential native controls, **not to qualify Premier League, Champions League or
cricket coverage**:

- NHL-owned current score confirms Washington–Philadelphia,28October23:30UTC,
  game2026020199, LIVE in period2 at00:39UTC on29October. The deployed fixture
  snapshot and native cached receipt corroborate tonight's exact identity.
- On182, CS and CNC both recorded `no_exact_fixture_match`.
- On183, CNC advances through the corrected exact match, returns two descriptor
  entries, then records `no_admitted_stream_delivery` with two rejections. One
  entry is an external/donation option. The media entry now advertises a
  different host, path and Referer/User-Agent contract, with Origin absent.
  It no longer matches the existing reviewed delivery contract. The adapter
  correctly keeps it out; no media fetch or security exception followed.
- CS's current hockey catalog contains the same pairing dated
  **29October23:30UTC**, explicitly upcoming,24hours after tonight's official
  fixture. Its live catalog has no exact current pairing. The15minute identity
  join correctly rejects this discrepancy. No source date was rewritten.

See the two redacted quality receipts and source-window diagnostics. Descriptor
HTTP200 and correct matching do not prove native playback. A changed delivery
contract requires a focused compatibility/security review before admission;
this gate does not implicitly approve another origin or header contract.

## Remaining live gates

- Fresh real Premier League and Champions League fixture plus exact provider
  metadata, admitted delivery, normal picker selection, correct-programme
  observation and90seconds of advancing decoded pictures.
- Supported AS cricket format/ordinal/Test-day identity with current on-field
  programme. The fresh ICC59of59 fixture receipt shows the ongoing Tests at
  STUMPS. Future TestDay2/Day3, ODI and generic channel rows do not clear the
  existing T20I/TestDay1 qualification gate.
- Actual same-attempt native fullscreen, Pause/Play, source switching and PiP
  background/return for the final candidate, followed by a real failing-primary/
  working-secondary case. These remain unexercised, not passed or failed by
  inference from the earlier181 football receipt.

AS catalogs changed during this window, from empty to populated. Consult the
final timestamped AS/ICC receipt rather than treating the earlier zero-count
observation as a permanent provider failure. At00:43UTC all five football rows
were accounted for: three future02:30UTC MLS fixtures, future12:30UTC
Aarhus Fremad–FC Copenhagen, and one generic Sky channel. The20cricket rows
include generic/future/unsupported-format candidates, not an established current
reviewed programme. The final refresh used five bounded metadata requests,
including one to resolve the initially omitted fifth football row. No media
request followed. Generic Sky and Willow/Fox channels
do not establish a named fixture's availability. In the normal app, existing
Willow/Fox rows had no stream listed, so no channel-control pass was claimed.

Jet was returned to landscape, Home/Football and keyboard capture OFF. No owner
video was left playing or source settings changed. Owned build products, private
preference/profile/device copies and the temporary keep-awake process are cleaned
at gate exit; only redacted verification and source hashes belong here.
