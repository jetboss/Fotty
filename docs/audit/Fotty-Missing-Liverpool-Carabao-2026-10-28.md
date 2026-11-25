# Missing Liverpool–Chelsea Carabao fixture — 28 October 2026

Scope: restore current football listings, add reviewed Carabao fixture coverage,
and make an accepted source-free fixture usable through existing enabled source
checks. Owner approved the focused repair, backend activation and Jet iPad gate.
Leave the phone, FPL and multi-stream unchanged; no TestFlight release.

## Confirmed causes and boundaries

- The primary broadcast publisher announced its closure. The three configured
  catalog mirrors share that publisher; they are not three independent fixture
  or stream inventories. A response from another mirror cannot restore an event
  the common publisher no longer lists.
- Deployed official football coverage included six football-data competitions,
  excluding the Carabao Cup. The app therefore lacked an independent official
  Cup row when the shared broadcast catalog omitted Liverpool–Chelsea.
- PL/CL/CPL-only interests intentionally exclude a Cup match. This is a separate
  visibility condition, not evidence that Carabao is a Premier League match.
  Current device preferences were not inferred from historical selections.
  Following Liverpool/Chelsea or whole Football includes a Cup row; an explicit
  PL-only browsing subfilter can still exclude it. Home's All sports/Browse
  sports retains the Only interests setting.
- A source-free official fixture could offer an optional add-on check, but the
  same action did not recognize the already enabled independent Score808 lookup.
  That stranded fixtures without a primary listing when no qualifying optional
  add-on was enabled. A fixture receipt itself is never a stream descriptor.

## Monitoring incident: detection did not become owner triage

- The deployed watchdog did observe a Streamed problem: [issue88](https://github.com/jetboss/Fotty/issues/88)
  was created27October04:57:08UTC after a `redirect-rejected` confirmation at
  04:31:16.603UTC. That observation was a rejected redirect, not proof of shutdown
  at that time. Neither the operator's reason nor the shutdown's start is known.
- The [daily provider run40732924653](https://github.com/jetboss/Fotty/actions/runs/40732924653)
  failed28October17:09UTC because no catalog qualified; Streamed returned HTML
  rather than JSON. The [observer run40735089352](https://github.com/jetboss/Fotty/actions/runs/40735089352)
  passed at17:22UTC. Observer success means its check/delivery process completed;
  it does not mean provider health, incident triage or owner receipt was verified.
- Detection is limited: the deployed probe checks `/api/matches/all` JSON shape,
  not live/upcoming routes or playback. Empty arrays and empty source lists pass.
  Three matching30-minute failed windows confirm an incident; notifications are
  GitHub issues. There is no active chat/push bridge. The separate fixture
  heartbeat was paused and scoped to fixture integrity, not broadcast publishers.
- At20:39UTC the public watchdog still expected playback version
  `2026-10-06.cricket-isolation-1`, while the EFL Worker reported
  `2026-10-28.efl-cup-1`. Exact-version compatibility requires rebuilding and
  requalifying the same published watchdog code with its flags, request budgets
  and retained incident state preserved. This later mismatch does not explain
  the earlier publisher closure or prove why an earlier notice was not read.

GitHub alerts are evidence of an observation, not automatic repair or verified
human delivery. No broader monitoring, chat bridge, automation or repair executor
was activated by this incident review.

## Focused repair

- Add the official EFL Match Centre source as isolated `efl-carabao-cup` with
  competition `carabao-cup` / `Carabao Cup`. Fresh EFL metadata at20:12:35UTC
  returned eight rows with matching counts; actual match `g2687775` named
  Liverpool–Chelsea, kickoff20:00UTC, period `FirstHalf`. UTC, explicit period,
  competition, exact response scope, counts and publisher receipt are checked.
  The existing durable registry preserves accepted facts as held on failure.
  See [the reviewed source contract](../operations/Carabao-Fixture-Source.md).
- Keep a dedicated default-OFF EFL activation flag, independent of general
  fixture/public-website flags. Production activation is owner approved and verified below. The absent/0
  default remains inactive for other configurations.
- Admit exact, unique verified senior Cup/provider joins without weakening
  date, squad, participant, competition-conflict or alias-recovery restrictions.
  Cup rows stay Other in the existing league tabs. Add an explicit Carabao
  interest option; do not migrate PL interests or broaden existing preferences.
- Allow Check streams through the existing enabled Score808 football/window
  policy, retaining exact current fixture identity, receipt freshness, terminal
  rejection, consent and completion rechecks. Dispatch through the existing
  independent discovery path; do not invent Watch, a source or LIVE status.

## Score808 omitted-visibility regression

At21:00:51UTC the existing public widget boot returned326 events. The exact
Liverpool–Chelsea row omitted `visible`, retained `repeatPeriod=noRepeat`, and
explicitly scheduled29Oct01:00–03:00 in `Asia/Karachi` (28Oct20:00–22:00UTC).
Its primary Watch Now action referenced the existing approved Score808 host.
The native `visible == true` guard incorrectly dropped the omitted field.

The boot advertised Elfsight Event Calendar2.53.9's
[shipped calendar script](https://universe-static.elfsightcdn.com/app-releases/event-calendar/stable/v2.53.9/89a18a9996c2cbc0e258350dcde7445b2ab76313/widget/eventCalendar.js).
The2,087,187-byte asset matched the boot's SHA384 integrity;
SHA256 `d445df9d74a90068c9b8c6f241a8847b6eb60b33d4ec558968fe626d47c08702`.
Its event normalizer at byte1129407 defaults the destructured visibility field
to true; the ordinary runtime caller at byte1249752 invokes it without the
include-hidden argument. This proves the missing-field default from shipped
code, rather than inferring it from a missing JSON property.

The focused decoder now defaults only an absent field to true. Explicit false
and null remain rejected; malformed types retain strict decode rejection.
Three deterministic Liverpool–Chelsea regressions cover the actual date/pair
shape, explicit visibility values and retained timezone/end/recurrence/action
restrictions. The final CS/relay/Score808 gate passes185 cases with one intended physical
skip. Later bounded Watch-page investigation found the calendar intentionally
links this listing article; its advertised HLS returned403. Score808 decoded
playback remains unqualified. No extra headers or access workaround was added.

## CS endpoint regression and actual playback recovery

The maintainer's [26October commit](https://github.com/rajhodedara/live-sport-plugin/commit/db40402f83ed8c060b6ed3deb1645ff63b564ae3)
adds `/api/manifest.m3u8` as a path-only alias of `/api/manifest`, preserving its
raw query and using the same handler. Fotty recognized only the old literal path.
Today's43 descriptors included35 alias rows, including31 safe nested HTTPS443
routes and four HTTP8008 routes that must remain rejected.

One shared exact predicate now admits old/new paths through initial validation,
wrapped-target validation, exceptional8443 binding and rotating-playlist binding.
The headerless alias explicitly selects guarded relay. No prefix matching,
arbitrary manifests, host/port expansion, credential/header changes or weaker
TLS/public-IP/redirect/nested-target checks were introduced.

The matched PPV route returned a valid master and child playlist, then an
advertised byte-range response206 containing131072 MPEG-TS bytes. This bounded
preflight justified preparing181; it was not itself a playback pass. Normal
Release181 on Jet subsequently discovered seven options through Home → match
details → Check streams. CS1 returned404 twice; automatic recovery selected CS2,
Native/Full HD. Actual Sky Sports Liverpool–Chelsea1–1 video advanced64:50→76:20,
more than ten minutes. EFL current metadata independently corroborated the exact
programme at68′/SecondHalf. Sources sheet, native fullscreen and native pause/
resume retained playback; landscape fullscreen was observed. Left CS2 playing.
Redacted telemetry records successful decoded progress in2718ms and the same
attempt entering native fullscreen. Audible output and PiP were not independently
verified in this focused gate. See [actual181 receipt](../testing/fotty181-playback-recovery-2026-10-28/README.md).

## Verification and delivered state

- Fixture/personalization/lookup:112 selected cases,111 initial passes; one newly
  invalid test fixture used Arsenal's name with Liverpool's participant ID. Fixing
  test data changed no production rule; all21 affected lookup cases passed on an
  overlapping rerun. AS52pass/one physical-only skip. Final CS/relay/Score808
  185pass/one physical-only skip. Skips are not live playback passes.
- Isolated backend67 tests, ESLint and Worker dry-run passed. Broader dirty-source
  95-case results are not the published artifact. Protected CI passed and
  [PR91](https://github.com/jetboss/Fotty/pull/91) merged as
  `c3ebfa018689bbcdfba02ab4c3ae4d897aa52dc9`.
- Production source `2026-10-28.efl-cup-1`, Cloudflare version
  `b3ff08d7-fe97-4ff4-87d8-eaad28792ad4`, verifies eight covered Cup fixtures,
  including actual `sports-fixture:carabao-cup:g2687775` at20:00UTC. Existing
  scopes, bindings, cron, secrets and unrelated activation flags remain unchanged.
- Owner separately approved the same-code watchdog compatibility rebuild:
  `d8c5e8cf-8de8-4321-9b04-43772349a0d0`. Its95offline+13workerd tests and dry-run
  pass; activation/budgets/incidents are retained. Exact-version
  [observer40766151178](https://github.com/jetboss/Fotty/actions/runs/40766151178)
  passes. No direct owner-chat bridge or automatic repair executor was added.
- Signed normal Release181 is installed on Jet. All313 input hashes match its
  prebuild manifest:15 changed against178,298 unchanged. All42 protected FPL
  hashes and multi-stream inputs match. All34 prelaunch settings slots and25
  post-playback nonvolatile configuration slots match. Phone untouched.
- Earlier179/180 receipts retain their original lack of decoded proof;181's
  actual native success does not retroactively qualify them. No TestFlight.

This closes today's missing-fixture and working-football repair for the verified
CS2 Cup delivery. The closed main publisher, CS1's404, empty AS row, unqualified
Score808 playback and missing direct owner alert path remain explicit limits.
No blanket all-provider, PL/UCL, cricket or future playback qualification.
