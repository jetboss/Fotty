# Fotty current state

14 Nov: [Jet 324 shared stream acceptance](../testing/fotty324-shared-admission/README.md): common delivery policy, per-entry accounting and separate selection ledgers. 2,678 tests passed, 12 skipped; signed normal 324 installed on Jet. Watch offered 26 choices (HF7/7, CS6/8, PP13/14; CNC unread). HF1 showed wrong rugby; HF2 held correct Vegas–Nashville 92s/zero stalls and recovered after a later failure chain. Programme mismatch cause remains unproven. No phone/FPL/multi/TF changes.

13 Nov history: [323 providers](../testing/fotty323-provider-watch/README.md), [322 CNC](../testing/fotty320-cnc-football/README.md), [319 Watch/Retry](../testing/fotty318-watch-availability/README.md).

12 Nov: Jet 317 fixed the relay deadlock and showed Curaçao–Panama at 0–0 in the 86th minute. Jet 316 fixed Highfly search. Internal TestFlight 287. Dashboard-only alerts. [Earlier Jet checks](../testing/fotty317-football-home-and-relay/README.md).

## Product and release baseline

[4Nov core viewing priorities](../testing/fotty-core-viewing-priorities.md).

Fotty: private iOS/iPadOS sports app prioritizing reliable single playback and native UX.
FPL/multi work paused. Shared2.0.1(206): Internal/Testing, Fotty Internal Smoke,13testers; notes “Bug fixes”.
Receipt:releases/Fotty-2.0.1-206.md.

## Discovery and retained follow-up

- Owner prioritizes working backup supply over extra alert/email work. Existing
  monitoring remains active; getfotty.com and direct email remain unavailable/OFF.
- The 4 November live campaign is expired. Its pending gates are historical, not authority for a new recurring check. Use fresh eligible fixtures and current owner authority; never reuse ended match pins. History: testing/fotty187-broadcast-reliability/ and fotty-resilience-2026-10-29/.

Audit:audit/Fotty-November-2026-Baseline.md.

## TV history 206–212

PR114/115 guides deployed; SkyCS1/beINTV17 holds and distinct CBS/Fubo/WillowSports failures: testing/fotty-tv-{expansion,recovery,next}-2026-10-31/.

## Cricket matching213/214 and Fox215

PR116/8298f54 deployed2026-11-01.cricket-matching-1 with existingwatchdog:
439backend/186watchdog checks; bindings/activation/incidents retained. Exact
CS/Willow cricket identity/IANA/ordinal/current-period guards persist. Jet214
TV1 passedits actualhold. Fox215 prototype276tests pass butSD/HDpicturewas
subscriptioncard, notFox;CS404/Flix504. UnqualifiedHTTP/ATS/helper removed216;
prototype retainedunapplied. Phone215installed16:17UTC, notagentlaunched, away.
216TV UI59tests passed, sourceacceptance incomplete. History:
testing/fotty-cricket-matching-2026-11-01/.

## 1 November broadcast history

217–219 added late alternatives, fresh TV discovery, bounded renewal and isolation of regressing rows without renewed leases. Jet Juventus TV4 passed a correct-programme 90-second hold. Willow TV1 alternated between decoded video and HTTP 404 while CS decoded; a later HLS response did not establish recovery. EFL empty-window repair remained local. See audit/Fotty-November-2026-Baseline.md, testing/fotty-liverpool-watch-2026-11-01/ and Decisions-Log.md for individual receipts.

## Watch feedback, fallback and Retry220

Watch reserves pending/Cancel feedback before validation; retained paused player
reopens without restart. Initial predecode timeout prefers an admitted current
exact alternative with positive history before same-route retry. Explicit Retry
refreshes index+CS/AS/Flix/CNC/SV metadata, same paths/limits/guards. Failed-pane
progress/Cancel and owner/attempt/intent/background fences cover second-alert Retry
and failure-only completions.166focused/26new tests pass0skip; signed app/widget220
installed/launched Jet. Home feedback and CS1/5failure→CS6decode observed; short
check isn't90s qualification or new startup-timeout branch proof. Physical Willow/
picker/Retry pending: shared Device Hub conflicts; Jet XCTest bootstrap timed out
awaiting UI Automation approval before methods ran. Owner action requested.
43FPL/multi source hashes+11stable preferences/source choices unchanged. No phone,
cloud/Git/TF work. Receipt:testing/fotty-watch-retry-2026-11-01/.

## Earlier optional work

Fotty2.5 optional gates and undeployed score-context work are historical: testing/fotty25-remaining-2026-10-29/Plan.md and Decisions-Log.md.

## Retained source baseline

Earlier184/183 receipts: testing/fotty184-source-native-2026-10-28/README.md;
no clearance of187PiP or target sports. Streamed is closed; preserve ordinary15min exact matching (with only the verified typed ODI/T20 early-coverage exception),
 TLS/public-IP/redirect/header and HTTP8008/2122 fences. Generic channels never
 identify fixtures. Established-player REA receipts remain dated evidence.

## Monitoring and fixture boundaries

- PR104config2026-10-29.native-catalog-parity-1 aligns ASselection/guardedmonitor-completion triggers; publishednormalcron verified. Originalactivation/finitebudgets/leases/notices preserved. Trigger diversity is not independent always-on delivery; Actions delays/Macchat remain limits. No email/push/humanreceipt proof.
- StreamExprimary/mirror converged onHTML-in-JSON; backupredirects.187fixeddiscovery60/90gap andprimary-onlyDetails without acceptinginvaliddata. Dateddiagnosis:testing/fotty25-remaining-2026-10-29/Broadcast-Failure-2026-10-29.md.
- Collector requires2matchingfailedwindows/2positivesforrecovery;emptyUNKNOWN. Budgets288CS/288AS/96others, no media/AI/autorepair. Failed deliverypending, revisionfences intact. PR125/5c074725 replaces ownermentions with one quiet issue45 dashboard; run41945708992 passed. Chatbridge PAUSED by explicit owner choice; dashboard only; grouped discovery-impact policy retains legacyreceipts, noinitialize/reset/replay. Append≠reading. DirectemailOFF. Operations:Watchdog-Owner-Alerts.md/Watchdog-Direct-Email.md.
- Deployed official fixtures: PL/CL/LaLiga/SerieA/Bundesliga/Ligue1/MLB/NHL plus
  EFL Carabao28Oct. Website/WNBA stay off. Preserve snapshots/backoff/conflicts;
  coverage follows deployed flags, not sport tiles. EFL Date/Age is artifact
  receipt, not event update time. Same-publisher checks aren't independent proof.
- CPL/WestIndies/ICC ownership retained; generic Willow/Fox names alone never identify matches.

## Other retained gates

- Older badge/AX/type receipts: audit/Fotty-Nine-Core-Fixes-2026-10-25.md.
  AS cricket/defaultOFF SV/UCL live gates remain open; never reuse expired pins.
- Sports sync OFF; widget/retry and141CS6PiP open. Preserve78WebKitPiP,
  badge/terminal/PL and off-main projection/audio fences. FPL/Coach unchanged;
  Catalyst fixtures prove no account. API-Football denied20Sep: no quota re-probe.
  Testers outside France.

## Non-negotiable boundaries

-256GB/8GB Mac: no simulators/concurrent heavy builds; one bounded output gate,
  disk checks and owned cleanup on failure too. Preserve others' artifacts/caches;
  keep-awake only for active approved work.
- Continue approved known repairs/install/testing on the named device without
  repeat permission. Source-only/audit gates do not imply packaging or publication.
  No phone substitution or interruption of owner playback; inspect availability.
- No TestFlight, Git publication, deployments, tester/roles, new accounts/spending,
  privacy/security expansion or destructive data operations without task authority.
- Homelab/remote embedding/PocketBase/Android/AceStream/P2P/Tailscale/Tunnels are
  retired. Active Cloudflare Workers are not retired tunnels.
- Never store credentials, signing material, private IDs/media URLs/tokens in
  memory. Sharing export redaction does not replace review.

## Topic routing

Playback: agent/playbooks/playback.md; UI: agent/playbooks/ios-skills.md; fixtures:
Architecture-Map.md; FPL: Project-Memory.md; release: agent/OPERATOR.md/Workflow.md;
memory: agent/playbooks/brain-ops.md.
