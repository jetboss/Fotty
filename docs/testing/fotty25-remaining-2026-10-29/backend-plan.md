# Fotty 2.5 — focused backend context activation candidate

Prepared 2026-10-29T18:11:20.571110+00:00. **Source-only preparation; nothing published or deployed.**

## Candidate and authority boundary

- Clean protected-source baseline: `origin/main` at `70e8b10d23d16d132e8f16559eb80d9b82441c43` (28 October, PR95). The tracking ref was refreshed read-only before preparation.
- Candidate release identity: `2026-10-29.sports-context-1`.
- The clean candidate was prepared in an owned temporary source archive and is retained as the exact review patch below. Temporary build/staging output was removed while owner access/activation approval remains pending; the dirty app working tree and its August HEAD/index were preserved.
- Exact review patch: [backend-context.patch](backend-context.patch) (also staged in the owned temporary gate).
- Patch SHA-256: `f92991d6f20c2c3192a589a61c43fa9b0bf8b3ffbb3243c016034a01271d78d5`.
- Exact per-file hashes: [backend-file-hashes.json](backend-file-hashes.json).
- 377 other archived files remain byte-identical to the protected baseline. Playback/watchdog configurations, CI workflows, lockfile, admitted sources, activation flags, quotas, bindings and durable migrations are unchanged.

Only ICC optional cricket context and football-data Champions League optional reported goals are transplanted. No unrelated per-record sports admission/isolation, provisional-time polling, aggregate503 change, web playback/dependency change, FPL, multi-stream, devices, source settings or TestFlight work is included.

## Explicit diff — 11 files, +570 / −15

| File | Diff |
| --- | --- |
| `web/package.json` | +1 / −1 |
| `web/workers/playback/src/cricket-context-policy.mjs` | +149 / −0 |
| `web/workers/playback/src/cricket-fixture-policy.mjs` | +8 / −4 |
| `web/workers/playback/src/cricket-fixture-policy.test.mjs` | +223 / −0 |
| `web/workers/playback/src/cricket-fixture-registry.mjs` | +6 / −3 |
| `web/workers/playback/src/sports-fixture-registry.mjs` | +4 / −3 |
| `web/workers/playback/src/sports-fixture-sources.mjs` | +6 / −3 |
| `web/workers/playback/src/sports-fixture-sources.test.mjs` | +14 / −0 |
| `web/workers/playback/src/ucl-reported-score-policy.mjs` | +61 / −0 |
| `web/workers/playback/src/ucl-reported-score-policy.test.mjs` | +97 / −0 |
| `web/workers/playback/src/worker-version.mjs` | +1 / −1 |

The package edit appends only the new UCL test filename to the protected `test:unit` script. It preserves the protected `hls.js` dependency and playback-controller test. The stage-only UCL registry regression additionally verifies admitted transport, score-only revision changes, nullable-score clearing and unchanged retained receipts after collection failure.

## Behaviour and compatibility

- Cricket reuses the existing admitted ICC response, exact enclosing fixture/team IDs and format/innings facts. Scores never infer LIVE, create fixtures or imply a broadcast. Explicit Stumps/break states remain explicit. Malformed optional context is omitted without discarding accepted fixtures. Bounded optional payloads preserve fixture counts and existing response ceilings.
- UCL reuses the existing six-league request; no additional source calls. Only exact senior-men's CL regular-time records with explicit integer goals and the publisher's existing timestamp carry `reportedScore`. Null prematch goals remain absent. PL/FPL score paths are untouched.
- Both routes retain schema1 and legacy fields. Older clients ignore the additive optional key. Existing snapshot/audit and old admission-path tests pass. A failed or held collection cannot create a new score receipt.
- Collection and public routes, source activation, rate budgets and privacy scope are unchanged. These are reported snapshots, not a ball-by-ball service.

## Offline verification

Runtime: Node25.5.0 (within project-supported `>=24 <27`), existing locked Wrangler4.127.1. No package installation, source/provider/media requests, Xcode/device work or deployment was performed by this staging gate. CI remains responsible for its pinned Node24 clean-install gate.

| Gate | Result |
| --- | --- |
| Cricket/sports policy, adapter, registry, real Worker runtime, audit and crosscheck tests | **215/215 pass; 0 failed, 0 skipped** |
| Existing watchdog offline policy/delivery tests and real Worker/transactional Durable Object runtime | **181/181 pass; 0 failed, 0 skipped** |
| Focused ESLint on all changed JS/test files | Exit0, warnings0 |
| Exact patch applies to clean baseline; whitespace error check | Both pass |
| Playback Worker dry-run bundle | Exit0; 248092 bytes; embeds new release identity |
| Existing watchdog compatibility dry-run bundle | Exit0; 126846 bytes; embeds same new release identity |

Redacted gate receipt: [verification.json](verification.json). The small test totals above are retained; owned raw logs, generated bundles and the temporary staging tree were removed after hashing. No duplicate dependency tree was created. Available disk was15GiB before preparation and19GiB after checks (other approved root-gate cleanup ran independently).

Playback bundle SHA-256: `a0d04732ef84c9776fd5cf70888191c7675605821c94d7f40b9902b67780e271`. Watchdog compatibility bundle SHA-256: `2b8b85540779dc5959b8794f0659c278265ededac2e1ce78b121cf15b5b4ecee`.

## Concrete remaining activation gate

1. **Owner authorizes protected publication and deployment of this focused backend candidate, plus the same-source compatibility rebuild of the already-active watchdog.** This preparation does not exercise that authority.
2. Before publication, perform one bounded existing-route ICC metadata read through the real parser/normalizer. Record only admitted/live/context counts, optional-ID type/binding validity and explicit phase. Completed18:12UTC through the clean candidate:59/59rows, both live-status Tests at Stumps, batting/bowling IDs are strings and bind to the exact admitted teams. See [live contract receipt](icc-clean-candidate-contract.json). This is metadata proof, not decoded media. Do not store the raw response, credentials or media URLs.
3. Apply this exact patch onto a clean current protected baseline; if `main` has advanced, review only the intersecting differences. Run the focused regressions plus full protected Web CI gates (clean `npm ci`, units, TypeScript, lint, Worker dry run and web build). Explicitly run/dispatch the watchdog CI gate: a playback-version-only change does not match its path triggers. Do not copy the dirty local package/config or publish unrelated staged fixes.
4. Merge through a protected PR. `.github/workflows/web.yml` verifies; it does **not** deploy. Deploy the merged playback code with existing production flags, secrets, bindings and accepted state preserved.
5. Rebuild/deploy the **existing** watchdog from that same merged release identity, preserving activation timestamp, runtime budgets/leases, incidents/outbox and configuration. `collectFixtureReceipts` requires an exact `/health` version; an old bundle stops fixture integrity reads after a new playback version. The GitHub observer's compatible-notice drift support is not a replacement for this rebuild. Do not initialize/reset private reader state or replay historical notices.
6. Verify exact public health revision and bounded cricket/sports schema/coverage receipts, plus normal watchdog completion/version match and retained state. A normal metadata success is not decoded playback, notification arrival or human receipt.
7. Finish the already-approved Jet-only native context/playback checks separately. Retain phone/FPL/multi-stream and no-TestFlight constraints. A dry-run or schedule-only UCL receipt does not qualify live UCL score/programme behaviour.

## Context freshness clarification

Protected playback cron is every5minutes. Cricket's adaptive collector uses5minutes for explicitly LIVE fixtures or scheduled starts within30minutes,15minutes for other starts within24hours, and4hours when quiet. The existing watchdog collector/observer's15minute cadence is separate.

Native context currently hides after10minutes using the actual ICC `observedAt`. Publisher lag or one delayed collection can therefore hide a scorecard even while fixture-status authority remains valid; a fresh HTTP response must not renew that timestamp. A truthful native follow-up is a distinct **last reported / updates delayed** presentation for10–30minutes, hidden after30minutes or immediately when held/unverified, with the reported time visible. Keep the existing30minute LIVE-status authority and identity/conflict guards unchanged. This backend patch does not change cadence or silently stretch context freshness.
