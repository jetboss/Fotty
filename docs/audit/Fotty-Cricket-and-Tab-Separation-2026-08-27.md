# Cricket discovery and focused tabs — 27 August 2026

## Approved scope

The owner asked to stop repeating FPL across Home and Matchday and to investigate
CPL through Willow Cricket. After the read-only findings, “proceed” authorized
implementation and tests. No server deployment, new subscription, direct-device
installation, external beta submission, or Git publication is part of this pass.

## Changes

- Home discovers fixtures and channels. It no longer owns an FPL callback, setup
  prompt, snapshot subscription, or squad-involvement badges.
- My Matchday contains explicit saved broadcasts and followed teams, not automatic
  FPL squad matches. Existing bookmarks and FPL manager/data/drafts are preserved.
  The redundant fantasy lens is removed from Match Center too. The FPL tab,
  deadline widget, and functional Settings/help entries remain.
- Cricket has All cricket, CPL and Channels filters. Known Willow/Fox channel
  identities render as a single channel, outside fixture/date rails, with an
  explicit programme-unknown explanation and a real source-gated Open channel
  action. They are not decorated as live CPL matches.
- Negative provider date sentinels no longer cause saved channels to expire.
  Channels have their own saved section in My Matchday.
- Shared timing replaces contradictory two-/four-hour logic: football retains
  its two-hour discovery estimate; identified CPL/T20 gets six hours; unknown
  cricket formats do not receive an inferred live/final state. These estimates
  are not official match results. Unknown other sports retain their bounded
  broadcast window but are not automatically marked finished after two hours.
- Football score lookups on changed cards require football category and kickoff
  identity. Cricket does not gain invented football scores or score-error labels.

## CPL schedule provenance and limitations

`CricketCatalog.swift` contains a small 39-fixture, season-bounded snapshot.
This is intentionally **not** presented as a dynamically refreshed schedule,
live-score API, EPG, Willow integration, or guarantee of streaming rights.
The UI states its check date and that the saved schedule may change.

Sources checked on 27 August 2026:

- [CPL's 28 April fixture announcement](https://cplt20.prezly.com/republic-bank-cpl-fixtures-confirmed-for-2026).
- [CPL's 27 July TKR correction](https://wp.cplt20.com/news/tkr-home-matches-at-qpo-tickets-on-sale/), with article text independently retrieved from its public [WordPress record](https://wp.cplt20.com/wp-json/wp/v2/news/20232): Jamaica is now the 29 August opponent; Guyana is now 31 August. Other dates/start times remain unchanged.
- [CPL's Barbados Tridents announcement](https://cplt20.prezly.com/barbados-franchise-to-play-as-tridents).

Explicit venue offsets preserve Jamaica's UTC−5 and the other hosts' UTC−4.
The 2026 snapshot expires after the final's continuity window and never rolls
into another season. Future beta releases during CPL must recheck league changes.
Playoff participants remain unassigned rather than being guessed.

Only a fresh catalog fixture with the same two franchises and a kickoff within
one hour can supply supported source identifiers to a schedule row. The row's
stable CPL ID survives this enrichment. Channel names, approximate competition
matches, wrong-date fixtures and cached schedule sources cannot supply it.
The dated snapshot by itself cannot produce a Watch action or a live claim.

## Provider investigation

The public current catalog lists Willow Cricket and Fox Cricket. Willow's source
endpoint returned six variants: HD/SD pairs for Willow, Willow 2 and Willow Sports.
Existing curation collapses those to distinct broadcasts. A catalog response or
embed URL is not decoded playback. The actual Catalyst player decoded Willow's
CPL coverage of Jamaica Kingsmen versus St Kitts & Nevis Patriots. The first
visual pass found an incorrect channel count suffix and “Willow Cricket vs Away”
title; the final build visibly shows `Cricket channels`, the single channel name,
`Open channel`, and a player titled `Willow Cricket`. Channels-only selection
removes dated fixture rails. No raw stream URLs are retained here.

## Verification

- Final-source unit run at 20:04 AST: **130 passed, zero failed, one opt-in
  reference-HLS soak skipped, zero unit runtime warnings**. Coverage includes
  channel identity/persistence, absence of cross-tab FPL dependencies, longer
  cricket timing, schedule dates/offsets/corrections, exact source matching,
  stable fixture IDs and season expiry.
- Five selected Catalyst checks passed in one final sequential run: cricket
  discovery/save-to-Matchday with text/description audits; setup dismissal with
  no FPL promotion; and Home, Matchday and Match Center Dynamic Type audits.
  The first cricket run exposed the known system-window description issue even
  in a clipping-only audit. Its final test explicitly audits descriptions too,
  with the existing narrow system-window exclusion, not an app-element waiver.
  The successful cricket run still reports a beta-Mac main-thread runtime
  warning; this is not a zero-warning claim for UI automation.
- The initial compile caught an invalid default for a required `Binding`; the
  actual caller now supplies that binding and the compatibility wrapper uses
  a constant. Subsequent unit and UI builds passed.
- Project plist validation, shell syntax and `git diff --check` pass.
- Final unsigned normal `Release` and `ReviewSafeRelease` builds both succeeded
  for generic iOS, sequentially with two jobs. These are compile checks, not
  signed archives or physical installs.
- Final live check used the existing muted QA configuration. Willow Broadcast 1
  remained selected while decoded media time advanced from 3 seconds to 27
  seconds and then 60 seconds, across 57 seconds of observation. The picture
  showed CPL coverage and the corrected single-channel title. No source switch
  or recovery state was observed in those samples. This is a bounded sampled
  continuity check, not proof of every frame, all six variants, future programme
  availability, audio/unmute, PiP or iPhone/iPad behavior. No playback-engine
  behavior was changed in this patch.
- The Computer Use skill guided actual Mac interaction and screenshot review;
  that visual check caught the channel title/count defects that policy tests
  alone had not covered.

Build 35 remains the distributed TestFlight release until a separate upload is
recorded. No simulator or direct device installation was used. All Xcode products
shared one owned, trap-cleaned temporary root. The test app was closed, that
approximately 1.4 GB root was deleted, and ten remaining owned temporary captures
were removed. No Xcode/test-app process remained; the final disk check showed
39 GiB free. Durable local project memory was refreshed successfully; the retired
homelab remained offline and no remote index sync occurred.
