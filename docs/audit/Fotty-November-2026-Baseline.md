# Fotty — November 2026 evidence and maintenance baseline

Reviewed 1 November 2026. This is a dated audit of the reported broadcast-refresh
incident, source contracts, supporting dependencies and their current verification.
It is not a claim that every app feature or every delivery has passed acceptance.
FPL, multi-stream, the owner's phone and TestFlight are outside this repair gate.

## Confirmed findings and resulting updates

| Finding | Concrete consequence | Repair and current evidence |
|---|---|---|
| A few regressing CS records rejected an otherwise useful registry snapshot. | Jet retained its 16:24 snapshot and missed fresh unrelated TV links. | Record/link isolation preserves anti-rollback and original leases; healthy siblings advance. 53 registry tests pass. Installed 218 accepted a 19:33 snapshot with no recorded `rejectedSnapshot` in that run. |
| Fresh cloud discovery outcomes did not enter Home's existing availability index. | Local collectors were suppressed, while Home could continue showing its primary-directory failure notice. | Import exact, fresh cloud outcomes through the existing ownership path, retaining original observation/expiry. Metadata imports do not reserve duplicate provider HTTP. 85 catalog/index tests pass. The 218 warning cleared after real source checks, without dismissal. |
| Earlier AS options could fail before slower alternatives arrived. | The same Watch attempt appended new choices without resuming selection. | Owned, bounded continuation considers newly arrived, never-failed matching choices. Pause, cancellation, replacement and background revoke authority. Actual 217 Elche Watch recovered to CS6 and recorded continuity; its separate refresh failure was not called passed. |
| Foreground CS and TV discovery could outlive the parent lookup; TV also depended on old accepted associations. | Valid late alternatives could be cancelled or omitted. | Foreground single-source CS/TV lanes allow 32 seconds and join a fresh bounded registry lookup. Aggregate and preflight limits remain unchanged. This is not a global timeout increase. |
| Flix's short-lived descriptor could expire while waiting in the picker. | A selected standby delivery failed before playback despite earlier discovery. | Existing single-player exact-choice renewal now includes Flix, with a six-second bound and stable identity/origin/path/header checks. Eight focused tests pass. A fresh media failure remains a failure. |
| A decoded Willow delivery stalled despite advancing playlist windows. | The existing frozen-window renewal path did not apply; the attempt terminated. | 219 extends the existing one-renewal budget to owned post-decode stalls with recent advancing-window proof and fresh exact-choice metadata. Negative ownership/security cases are tested. The 218 hold failed; the original starvation cause remains unproven. Native 219 outcome is recorded separately, not inferred from unit tests. |
| A freshly verified scheduled fixture disappeared at kickoff before the status publisher caught up. | Juventus–Napoli vanished from Home's upcoming section even though fresh official status corroborated play. | 219 retains the existing row as **Starting** within the existing 30-minute freshness bound. It does not invent LIVE status or a live count. Scheduled lookup uses fresh identity evidence; terminal/conflict/held checks remain. |
| EFL's exact official empty-window response is HTTP 404 with `No matches found`. | Expected emptiness accumulated as a repeated source failure. | Exact response-contract handling, scoped to the reviewed EFL request, passes 45 tests and a Worker dry run. Other 404s and loss of accepted active facts still fail. **Source-only; not deployed.** |
| Web packages and the local runtime selector needed maintenance. | An unsupported runtime could be selected and known package fixes were absent. | Next/eslint-config-next 16.4.3, sharp 0.35.5 and project Node 24.22.2 were validated in an owned staging tree. Four selector tests, 46 web tests, types, lint and production build pass. No website deployment or replacement of the owner's existing node_modules/.next. |

The 219 combined native selection passed **263 tests, zero failures/skips**.
Selections above overlap; their counts must not be added into an invented total.
Compilation and native installation/observation have separate receipts.

## Final private iPad result

Private219 was signed, installed and launched normally on Jet iPad. Normal Home
Watch selected TV4 for Juventus–Napoli, automatically recovered an initial
transport error, decoded at20:27:32 UTC and recorded positive90second continuity
at20:29:02. Correct programme and an advancing match clock were observed. Home's
refresh notice cleared after checks without dismissal or manual refresh.

Willow's separate219 test failed both startup attempts before decoded video.
It did not exercise the new postdecode recovery branch; that branch's physical
acceptance remains open. No confirmed local cause supports another timer/buffer
change or build. This candidate is **not fully stable** and no TestFlight release
was performed. See the separate [successful normal Watch receipt](../testing/fotty-liverpool-watch-2026-11-01/219-native-watch-receipt.json)
and [failed Willow receipt](../testing/fotty-liverpool-watch-2026-11-01/219-willow-failed-receipt.json).

The later owner session corroborated that Willow can play: TV1 decoded at22:38,
then returned404 after reselection; CS decoded as well. At22:46 the same publicly
advertised Willow locator returned200/HLS. These varying responses do not prove
stable playback or identify the historical404 cause. The [owner follow-up receipt](../testing/fotty-liverpool-watch-2026-11-01/219-owner-willow-cs-followup.json)
also records confirmed acknowledgement and retry-order shortcomings. No code or
device settings were changed by this read-only follow-up.

## What was already current

- Installed Xcode 27.2 / Swift 6.4.2 were checked. Swift language mode 5.9 is not
  evidence of an old compiler. No checked-in native package dependency migration
  was needed for this incident.
- Source-access, exact identity, squad/date/format, expiry, TLS/public-IP,
  redirect/header, cancellation and lifecycle restrictions remain in place.
- Worker compatibility dates express a reviewed runtime contract. A newer date
  alone does not justify changing that contract or deploying a bundle.
- Official fixture identity, provider broadcast association, descriptor admission,
  native decoding and sustained viewing are separate facts. One cannot prove the
  others. Empty overnight catalogs and future fixtures are not playback failures.

## Remaining limits and gates

- An upstream 403, unavailable delivery, payment card, conflicting source time or
  wrong programme remains disqualified evidence. The Fox 215 prototype displayed
  a subscription card; it is not a Fox playback pass and its exception was removed.
- The failed Willow 218 hold remains failed. Advancing relay samples and successful
  segment requests did not establish the root cause or sustained playback.
- Five-minute fixture collection, five-minute native refresh and public caching
  can delay status changes. The actual fixture account tier was not inspected;
  do not attribute delay to a paid/free tier without evidence.
- AS cricket, UCL and other previously pending live gates need their own freshly
  eligible fixture. Do not reuse an ended event or turn skipped checks into passes.
- New EFL backend behavior requires a protected publication/deployment gate before
  production can be called repaired. Existing production flags and watchdog state
  were not changed by this audit.
- The global Node 25 default was left unchanged. The project has a durable official
  Node 24 runtime and bounded selector. A failed Homebrew attempt had partial
  library-bottle effects, recorded in the maintenance receipt; no broad rollback
  or lock deletion was attempted.

## Keeping evidence current

1. Start from the installed build, deployed revision, activation flags and original
   publisher contract. Historical notes are receipts, not current authority.
2. Recheck a suspected source change with bounded fresh metadata. Preserve accepted
   facts and contradictory receipts; do not renew old proof from cache timestamps.
3. Update dependencies through the existing weekly Dependabot lane and a verified
   project runtime. Validate targeted behavior before deployment; avoid unrelated
   major migrations during a playback incident.
4. Maintain an explicit table of implemented, compiled, installed, decoded and
   sustained-playback evidence. Re-test affected paths and lifecycle boundaries,
   not every healthy feature after every build.
5. Keep November's current summary short and route to these dated receipts. Do not
   erase October history or relabel old failed runs as successful.

## Inspectable evidence

- [Incident, native observations and repair receipts](../testing/fotty-liverpool-watch-2026-11-01/README.md)
- [219 combined test result](../testing/fotty-liverpool-watch-2026-11-01/219-recovery-starting-tests.json)
- [Web/runtime maintenance, verification and primary sources](../testing/fotty-liverpool-watch-2026-11-01/november-web-maintenance.json)
- [EFL exact empty-window comparison](../testing/fotty-liverpool-watch-2026-11-01/november-EFL-empty-window-comparison.json)
- [EFL focused tests](../testing/fotty-liverpool-watch-2026-11-01/november-EFL-tests.json)

Public maintenance references were checked during this audit: [Node release
support](https://nodejs.org/en/about/previous-releases), [official Node archive
checksums](https://nodejs.org/dist/v24.22.2/SHASUMS256.txt), [Next security
advisory](https://github.com/vercel/next.js/security/advisories/GHSA-2464-fhr4-w9xw)
and [published Next package metadata](https://registry.npmjs.org/next/16.4.3).
Announced future releases are not represented as installed fixes.
