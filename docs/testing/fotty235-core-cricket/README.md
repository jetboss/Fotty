# Core cricket repair — private Jet 235

4 November 2026. Phone, FPL, multi-stream and TestFlight remain excluded.
This is a partial qualification receipt, not a release clearance.

## Implemented and installed

- Signed normal Release 3.0.0(235) installed on Jet; app/widget signatures verified.
- Current programme presentation requires fresh, unconflicted registry association
  to one official fixture. An unassociated/finished programme cannot remain “On now”.
- Native and cloud Willow WBBL matching accept the reviewed women's T20 programme
  without inventing a match number. Official CA identity, squad, time, status and
  unique-match checks remain required. Explicit ordinal conflicts remain rejected.
- 104 focused native tests passed, zero skipped. Signed iOS Release compile passed.
- 17 protected preferences and 42 FPL/multi-stream source hashes unchanged.

## Published collector and production regression

PR [122](https://github.com/jetboss/Fotty/pull/122), merge
`aa79e82e1d560b06129ecb74ea423305b282bd03`, adds isolated official Cricket Australia
WBBL collection. Published candidate: 589 backend tests, 186 watchdog checks,
changed-module lint and both bundles passed. Existing activation, durable bindings
and 141 watchdog notices survived deployment; only the approved WBBL flag was added.

Production collections at 14:05:05 and 14:10:05 UTC failed before collecting rows.
The same collector succeeded in Node. Running the exact code under workerd with
deployed compatibility flags identified the cause: workerd rejects `redirect:
"error"` before sending a request. Node fetch mocks had not exercised that runtime.
Existing ICC/CPL facts survived the new cohort's failure.

PR [123](https://github.com/jetboss/Fotty/pull/123) changes this to supported manual
redirect handling, still rejecting every non-OK response. The new actual-runtime
test fails against the published code and passes with the correction. It also
proves 301/302/303/307/308 targets are never fetched. Candidate checks: 590 backend,
186 watchdog, lint and both bundles passed. All three protected GitHub workflows
passed; merged as `a7ec1b37aabbbb25b02fa09f6edd79a14bfe6aca` and both Workers deployed.
At 14:20:39 UTC production accepted ten WBBL rows, zero consecutive failures.
Jet235's real native cache subsequently contained all ten rows. All 22 playback
and three watchdog binding/settings records remained equal to the pre-correction
snapshot. The normal watchdog cycle completed at 14:30:59 UTC; paired-deployment
verification passed with all 141 notices retained (`deployment-safety.json`).

## Physical channel evidence

These are normal channel tests, **not** exact live-match Watch qualification.

| Channel/build | Observation | Evidence |
| --- | --- | --- |
| Fox Cricket/234 | Actual Fox501HD women's Heat–Sixers pictures, not the former subscription card | 13:26:21.905 UTC tap → CS1 decoded 13:26:31.692: 9.786 seconds. Native hold 93.190 seconds, zero stalls, 1920×1080. |
| Fox automatic recovery/234 | CS1 later stalled; CS3 took over without manual source selection | Failure 13:29:57.552; failover 13:29:57.570; CS3 decode 13:30:14.699: 17.13 seconds. Replacement held 91.937 seconds, zero stalls, 960×540. Both routes are CS; independence is unproven. |
| Fox resume/234 | Resume eventually recovered the native live window | Recovery operation took 1.58 seconds, but the tap-to-resume interval was not measured reliably. This is not a fast-resume pass. |
| Willow/235 | Immediate opening feedback, then actual Willow-branded South Africa–Australia replay pictures | 13:59:41.133 tap → TV1 decode 13:59:47.074: 5.941 seconds. Held 91.960 seconds, zero stalls, 1280×720. Details did not claim the finished NZ–India match was current. |

`channel-evidence.json` contains finite telemetry only. Correct-picture observations
are separate from player-clock evidence. Neither replay establishes current live
fixture coverage. Latest screen observation at 14:17 UTC still showed Willow video.

## Remaining acceptance

- Corrected CA production collection, native cache admission, retained finished
  match9 and post-deployment normal watchdog cycle are verified.
- Verify exact Willow/Fox fixture-to-edition association through normal match Watch
  during a freshly corroborated live window. WBBL match9 is finished; do not reuse it.
- Fresh original Foxtel guide access recovered on4November around14:54UTC.
  FOX CRICKET HD programme ancestry includes absolute epoch starts, current replay
  titles and explicit Live WBBL titles. The next Strikers–Heat entry corroborates
  CA5November04:40UTC; Thunder–Scorchers coverage begins08:00UTC before08:10kickoff.
  This is source-contract evidence only: no Fox guide parser or activation yet.
- PL/UCL/current cricket independent-backup acceptance remains open. Two CS routes
  and a generic channel tune do not satisfy independent same-match recovery.
- Owner reports persistent play/pause overlay. A confirmed counter defect treated
  normally advancing single-player video as one stagnant sample, while auto-hide
  required zero. The local repair clears healthy progress, rearms after a recovered
  stall or closing the source picker, and preserves paused/accessibility controls.
  94 focused controls/fullscreen tests pass without skips. Test-only Catalyst target
  overrides accommodate this Mac; production deployment targets are unchanged.
  Signed normal Release236 is installed on Jet. Physical Fox playback showed the
  controls disappear automatically, remain visible throughout deliberate pause,
  and disappear after resume. Source-sheet dismissal also rearmed the fade without restarting CS1.
  These observations were made14:39–14:41 UTC. All13 protected preferences and
  42 FPL/multi source hashes remain unchanged; owner-selected Light appearance
  was preserved. See `controls236-evidence.json`.
- Broader Willow/Fox competition coverage is not complete merely because WBBL is added.

No TestFlight upload or phone operation occurred in this gate.

## Build 236 separate delivery failure — 14:32 UTC

Willow TV1 returned HTTP404 during manifest contract validation. Automatic fallback
selected CS1 and decoded at14:32:38 UTC, then stalled at14:33:08. Explicit Retry
showed pictures again but stalled again. These failed runs remain separate from
the earlier235 hold. CS1 recorded CoreMedia-12888; the last relay playlist sample
was advancing with preserved metadata and no relay request failures. That does
not establish the underlying cause of every stall. No source rule was weakened.

Fox236 subsequently displayed Fox501HD Heat–Sixers footage and passed its native
90-second advancing hold with zero stalls. Pause/resume recovered the same CS1
attempt; the native resume operation recorded2043ms. This remains a channel/replay
check, not live-fixture or independent-backup acceptance.

## Additional Willow delivery237 — physical channel check

Fresh CS3.1.3 main-US-Willow metadata advertises a distinct CDNLive direct HTTPS
HLS delivery that the existing adapter rejected. Its public Origin/Referer/User-Agent
contract and literal token are now admitted only for the reviewed origin/path.
The normal guarded relay and identity/redirect/public-address checks remain.
The old adapter fails the focused regression; repaired CS and relay suites pass
229 tests, zero skips. A returned playlist is not a native playback pass.
See `cs237-evidence.json` for physical status. No publisher-independence claim.

Signed normal Release237 (app/widget verified) is installed on Jet. All229 CS/relay
tests passed. Normal SportsTV Watch opened TV1; its source picker now contains
TV1, CS1 and the additional CS2 delivery. Selecting CS2 at15:04:50UTC returned
upstream manifest503 twice; automatic fallback decoded TV1 at15:04:56.882 and
held92.059seconds without stalls. The failures are preserved. The unchanged
advertised URL returned200 from Mac Node and Foundation requests. A manual
CS2 Retry at15:07:42.539 decoded at15:07:48.041 and held93.664seconds with
zero stalls. Correct Willow-branded NZ–India ODI replay pictures were observed.
This proves a usable additional channel delivery, not consistent first-attempt
availability, publisher independence or a live-match registry association.
43 excluded source hashes and12 protected preferences remained unchanged.

CS2 deliberate pause retained the Play control; resume recovered the same attempt
in507ms and auto-hid controls. Access-log stall count at resume was1 (the prior
93.664s acceptance hold recorded0); do not describe the entire session as stall-free.
A nearby AirPods prompt appeared during the later observation and was dismissed
without connecting or changing audio settings. No terminal failure occurred.


## Fox original guide — local coverage review, 15:21 UTC

A fresh bounded original Foxtel FOX CRICKET HD page contains 24 programmes with
explicit epoch timestamps. The current Heat–Sixers programme is a replay, not a
live-fixture authority. Two subsequent live WBBL programmes corroborate uniquely
against fresh Cricket Australia fixtures: Strikers–Heat at 5 November 04:40 UTC,
and Thunder–Scorchers coverage at 08:00 UTC for the official 08:10 UTC start.

The local pure parser and coverage-review helper pass nine focused tests covering
replays/pregame, conflicting descriptions, hidden markup, duplicate ancestry,
source limits, stale/ambiguous official facts and exact women's T20 identity.
The parser never invents LIVE fixture status or a final programme end. The tests
are included in the existing unit-test inventory.

This is metadata evidence only: no cloud collector or native Fox programme bridge
has been activated, no new event-use permission is inferred, and no live Watch
qualification is claimed. Existing registry access policy and native station/
programme validation still need an end-to-end integration. No device interactions,
additional build, publication or deployment occurred for this parser check.
See `fox-guide-evidence.json`. Owned raw guide output was removed after review.


## Fox collector boundary — staged, 4 November 15:34 UTC

The actual bounded shared-source collector now has an explicit, default-off Fox
programme option. It parses the original Foxtel page through the existing request
reservation, byte cap, timeout and no-redirect transport. Current explicit WBBL
programmes become guide references, not a fabricated TV delivery. Original
programme times and the absence of an ordinal remain intact; official CA fixtures
supply the independently validated match number at association.

Fox and Willow collection failures remain isolated, with partial coverage rather
than an exhaustive-empty claim. Durable-state tests prove that fresh Fox evidence
cannot renew the retained Willow programme lease, including across restart.
172 focused tests pass with no failures/skips; Worker dry-run bundle succeeds.
The real collector received HTTP200 from both original guide publishers using two
reserved requests at15:34UTC, with no current qualifying live programme. The
separate15:21UTC original-guide/official receipt records two upcoming WBBL matches.
Neither result is media/playback proof.

**Remaining at that checkpoint (superseded by the integration receipt below):** native guide-to-Australian-CS-channel support;
resolution of the existing explicit new-station event-use policy (the collector
has not fabricated or bypassed clearance); consumer/version compatibility;
reviewed-TV refresh accounting for the possible fourth request at a Willow date
boundary; then protected publication/deployment and actual live Watch acceptance.
Production does not enable the new collector option. Phone/FPL/multi-stream,
settings and TestFlight remain untouched; Jet stays on237.
Receipt:`fox-collector-evidence.json`.

## Fox match integration — local validation, 4 November

The native existing-match path now joins a current reviewed Fox WBBL programme
to an enabled CS channel with explicit Australian edition evidence. Fresh catalog
and same-ID metadata must still agree before requesting media. Guide-only rows
do not become fake TV sources. Original programme expiry bounds the resulting
session; wrong market, changed metadata, opt-out and expired guide cases reject.
Explicit access restrictions remain effective; default reviewed matching adds no
global entitlement claim and changes no stream transport or security checks.

222 native tests pass, zero failures/skips. The first integrated run had220 passes
and2 failures because the new test fingerprint included a squad field that the
actual canonical cricket loader does not emit. Test data was corrected against
the real loader and native schema; that admission guard was not weakened.
Earlier test-helper actor annotation compilation errors were also corrected.
The failure summary remains in `fox-native-integration-evidence.json`.

296 focused backend tests and251 watchdog tests pass; both Worker dry-run bundles
pass. Older clients receive their unchanged generic Fox channel and no new Fox
guide rows or AU proof. The native candidate advertises the new capability.
Fresh Willow timezone hints choose the initial requested civil date, never supply
programme authority. Every page must still pass original station/date/zone checks.
Hints survive restart without lease renewal and expire after four hours. This
keeps Willow, Fox and ESPN within three reads per collection and the existing576
daily allowance. A cold date correction defers Fox for one cycle when ESPN also
needs its reserved slot; partial coverage does not mean exhaustive absence.

Candidate version: `2026-11-04.fox-programmes-1`. Production activation remains
OFF pending the separately requested owner approval. A rollback must retain the
compatible state reader: an older Worker rejects stored AU market records.
Disable new Fox collection on compatible code rather than resetting accepted
state or blindly reverting the binary. No publication, deployment, device build
or device interaction occurred in this integration gate; Jet remains237.
Actual live Fox-to-match Watch and independent-backup acceptance remain pending.

## Fox release 238 — rollback validation and private install, 4 November

The rollback caveat above is superseded: durable Fox channel records now use the
legacy-compatible shape plus a source-root hash proof of the exact AU record.
The actual prior deployed reader accepts the state and preserves the generic
channel; the current reader restores AU only when the complete record still
matches that proof. Reads do not rewrite accepted state or extend expiry.

The isolated release passes 672 playback/published-watchdog tests, type checking,
lint and both bundles. Two test-only CodeQL hostname comparisons were replaced
with exact parsed-host checks; all eight affected tests pass. Signed normal
Release 3.0.0(238) is installed and launched on Jet. Sports TV renders normally;
27 checked preferences and 42 FPL/multi-stream source hashes are unchanged.
PR124 is published under owner approval; protected CI/deployment verification
is still pending at this checkpoint. Current Fox programming is a replay, so
this is not live match-to-channel playback or independent-backup qualification.
See `fox-release238-evidence.json`.

### Deployment verified — 4 November 16:46 UTC

Owner-approved PR124 merged as `c12a800c8bbab78feae4ca583f485008a233fe5d`.
All twelve candidate files matched the protected merged revision before upload.
Playback and the existing watchdog now run `2026-11-04.fox-programmes-1`.
Fox collection is enabled; other live bindings/flags, original watchdog activation
and all 141 notices are unchanged. A normal TV collection completed16:45:36UTC
and the normal watchdog completed16:46:09UTC. Paired post-deployment safety passes.
This is real scheduled collection, not synthetic-canary evidence.

Current and legacy registry views returnHTTP200. The fresh cricket programme
result is legitimately empty during replay programming; this does not assert
that no cricket channels are playable. Jet238 accepted a post-deployment
16:39:31UTC snapshot with1700broadcast records and52links, including the generic
Fox channel. Home/TV render, the prior TV tab was restored, source/user settings
were preserved; app-maintained quality records updated during refresh. No
preference file was written. Forty-two FPL/multi-stream source hashes remain
unchanged. One CoreDevice terminate-and-launch response failed to determine a
PID; ordinary launch succeeded and the app accepted fresh data. This alone is
not evidence of an application crash.

**Still pending:** normal Watch selecting Fox from a genuinely live matched
WBBL fixture, a correct-programme native hold, and independent-backup acceptance.
The original guide currently shows replay; the next reviewed live match window
is5November04:40UTC and must be reverified when in progress. No TestFlight
readiness claim or distribution, phone interaction, FPL or multi-stream change.
Detailed redacted receipt:`fox-release238-evidence.json`.

## Coverage preflight and next live acceptance — 4 November 16:49 UTC

Bounded fresh original Willow/Foxtel guide pages, the fresh deployed official
fixture feeds and six CS metadata reads were compared. Willow currently carries
highlights; Fox carries a replay. The next reviewed Fox WBBL matches are present
in CA fixtures and recognised. Willow recognises Afghanistan–Zimbabwe first
Test days1/2, excluding Preview/Review. ICC publishes05:00UTC on5November;
Willow live coverage begins07:00UTC. Preserve both times. The scheduled official
fixture has no current live day/ordinal context yet; this must be reverified
when in progress, never manufactured from the guide or a countdown.

The plain CS Networks page has100 rows and omits Fox, but the regular Cricket
cohort contains the exact Australian NETWORKS Fox row, also returned by its
advertised search. No additional search workaround is justified by this data.
Existing stored AU proof waits for normal collection; no source opts/settings
or security rules changed. Current contracts recognise the observed upcoming
programmes; this is not a promise of unreviewed future competition coverage.
Receipt:`coverage-preflight-2026-11-04.json`.

UEFA and the fresh fixture snapshot agree on Fenerbahçe–Liverpool and
AEK–Real Madrid at17:45UTC/13:45Tobago on4November. A single bounded Release238
physical Watch/outage gate is being prepared, with a normal signed restore app.
No installation, live-fixture pin, source failure or media test has run in this
preparation. Require fresh in-progress status before pinning the test; keep
settings and the phone/FPL/multi-stream untouched. No TestFlight.

### Focused UCL238 gate prepared

Both sequential signed Release preparations succeeded: the normal restore app
and the private fixture-scoped outage harness. No source-code edit, new device
install or physical test occurred in this continuation. No future fixture has
been pinned as live. One owned gate is retained only for this named4November
match window: `/private/tmp/fotty-coverage-238.yb4caj9o` (marker
`/private/tmp/fotty-coverage-238-gate`). Reuse its single DerivedData directory.
Original run: `DerivedData/Build/Products/FottyFoundationUI_iphoneos27.2-arm64.xctestrun`;
normal restore:`Restore/Fotty.app`. Compilation session61607 completed exit0.

Once a fresh eligible fixture is in progress, run the existing
`tools/testing/prepare-jet-watch-drill.py` with `--force-source-failure`, then
set `FOTTY_TIMED_INDEPENDENT_DRILL=1` in the generated target environment so the
normal selection policy is exercised and actual startup/replacement timing is
captured. Inspect Jet availability before any installation or interaction.
The app's provenance marker establishes different catalog families/origins;
independently inspect pictures and delivery provenance before claiming an
independent upstream. Retain failures/skips separately; restore normal238 or
newer after the gate and clean owned products.

Read-only renewal tracing found the resolver obtains a new current programme
association before re-resolving the selected channel. The adapter's same-guide
checks apply to that newly supplied association during the request, not to an
indefinitely retained old programme. No speculative renewal patch was made;
this source review is not long-duration live playback proof.
Receipt:`ucl238-prepared.json`.

### 4 November UCL Watch failure and recovery repair239

Fresh UEFA match2049622 confirmed AEK–Real Madrid LIVE/FIRST_HALF at17:51UTC;
the deployed football-data snapshot still said scheduled. An externally verified
test pin changed neither app nor fixture data. Normal Watch on Jet238 mounted
CS1 but did not reach advancing native video within100seconds. No forced outage
or primary/backup hold passed. The trace reports startupTimeout followed by
“current fixture unavailable” and descriptor_fixture_changed. Normal238 was
restored successfully. Failed receipt: `ucl238-failed-startup.json`.

Confirmed boundary defect: scheduled match Watch/registry admission uses a fresh
identityReceipt, but RegisteredDescriptorRecoveryPolicy incorrectly requires
freshness of the older publisher status-change timestamp. Local239 uses the
identity receipt for scheduled sports fixtures only. LIVE freshness, terminal,
team, squad, kickoff and current-catalog checks remain. Added focused regression
coverage for admission and switching plus stale/terminal/changed-identity vetoes.
Release app compiled, but the unit test target requires Debug-only helpers; that
configuration failed before tests. The subsequent Debug test build was cancelled
when the owner asked to watch Liverpool; no passing239 test/install is claimed.

At18:03UTC a read-only Jet view showed Fenerbahçe–Liverpool already playing full
screen on TNT Sports1 at14:03. The agent did not select this source. Preserve that
owner playback: do not install, launch tests or change sources while it is running.
Phone/FPL/multi-stream/TestFlight untouched. The same bounded build gate is retained
for this match window; no keep-awake or test process remains running.


## Liverpool239 — recovery repair installed, commentary restored

Normal Release239 compiled, passed signature verification, installed and launched
on Jet. Its scheduled-fixture recovery correction let automatic source fallback
reach CS4: the correct Fenerbahçe–Liverpool/TNT Sports1 picture advanced from
33:38 to35:39. This was **not a successful audible session**: the owner confirmed
silence, diagnostics reported audio_enabled=false, and the scene displayed the
web/native audio transfer failure. Both findings remain preserved.

A clean normal launch followed by Sports TV → TNT Sports1 restored TV12. Native
diagnostics show audio_enabled=true and actual decoded progress; the owner
explicitly confirmed commentary. One startup timeout/retry and a decoded stall
preceded the later start, so neither an uninterrupted90s hold nor independent
failover is claimed. Leave this owner's game running.

The permanent audio handoff candidate is source-only so far: actual mounted Web
owner tracking, exact retained teardown callback, late-ACK single focus recovery,
Retry audio without restarting the stream, and local handoff outcomes. Focused
Catalyst unit tests use current source and mocked transports, not the old Mac app
or a claim of physical audio proof. No installation of this candidate during the
game. The refreshed Home/Search Liverpool listing separately became unconfirmed;
that is not fixed by an audio repair. See liverpool239-recovery-and-audio.json.

Final local check: **15 focused tests passed,0failed,0skipped**, covering scheduled
fixture recovery, actual-vs-uncreated Web ownership, cancellation/retirement,
wrong/late callbacks, automatic single audio recovery, preserved player/item/Pause,
and unchanged two-pane focus fences. Initial14-test run also passed; the final
incremental run includes the added return-to-single ownership regression and all
final source changes. This is not an installed audio candidate or audible physical
acceptance. The owner remains on normal239 with confirmed TNT commentary.

### 4 November — Home retention repair before full time

Confirmed Home section omission: a current match downgraded to unconfirmed remained in Search but entered no Home section. Both layouts now retain elapsed football fixtures neutrally for four hours, preserving terminal/conflict vetoes and existing Watch/source eligibility. Fresh status restores live placement. 41 focused current-source Catalyst tests pass, zero failures/skips, including four new regressions. Two outdated assertions in the existing empty-Home test were corrected to existing behavior; earlier failed receipts are summarized in the Liverpool239 JSON. This does not prove why the upstream status became stale. No device interaction; consolidate with the audio fix only after official full time.
