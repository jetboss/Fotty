# Fotty current state

21 Nov: [TestFlight344](../releases/Fotty-3.0.0-344.md) VALID (prior 343): bad reads never break confirmed matches (6 h grace; live to kickoff+3 h); app ESPN backup; never "delayed". Worker 0a92e849 (PR137): failed reads keep facts; /api/sports/history; 10-min monitor.

15 Nov: [Jet337 Highfly integrity](../testing/fotty337-highfly-programme/README.md): Claude approved participant corroboration and query-safe renewal, preserving ranking.2,744 tests pass/12 skips; first visual-cache failure retained. Normal337 installed. Spain Watch recovered to correct CS2,92s/zero stalls. HF on Spain/Belgium supplied Google-hosted deliveries and failed predecode; Belgium exhausted backups. Initial wrong-programme cause/HF qualification remain open. Phone/TestFlight unchanged.

Prior336: [Watch freeze/discovery repairs](../testing/fotty336-watch-failures/README.md),2,739 passes/12 skips; correct channel holds. Prior335 [UI](../testing/fotty-core-motion-20261115/jet335-acceptance.md) and334 [guide](../testing/fotty-sports-tv-guide-20261115/jet334-acceptance.md) receipts retain their limits.

14 Nov: [Jet332 retirement](../testing/fotty332-watch-first-retirement/README.md): FPL removed, Watch Two parked; saved data/scores/follows/ranking preserved. Claude approved;2,687 tests pass/12 skips; correct WBBL Watch91s/zero stalls. Shipped as TestFlight332.

14 Nov: [Jet324 shared admission](../testing/fotty324-shared-admission/README.md) added common delivery policy and accounting. HF1 showed wrong rugby; HF2 held correct Vegas–Nashville92s/zero stalls. Programme mismatch cause remains unproven; receipt retains source counts and recovery evidence.

13 Nov history: [323 providers](../testing/fotty323-provider-watch/README.md), [322 CNC](../testing/fotty320-cnc-football/README.md), [319 Watch/Retry](../testing/fotty318-watch-availability/README.md).

12 Nov: [Jet317 relay/316 Highfly history](../testing/fotty317-football-home-and-relay/README.md); dashboard-only alerts.

## Product and release baseline

[4Nov core viewing priorities](../testing/fotty-core-viewing-priorities.md).

FPL retired; Watch Two deleted 19 Nov (owner: rebuild later). Preserve legacy data, public scores and single-player behavior. Shared 3.0.0 (344): Internal/Testing, Fotty Internal Smoke (previous 343).
Receipt: releases/Fotty-3.0.0-338.md.

## Discovery and retained follow-up

- Owner prioritizes working backup supply over extra alert/email work. Existing
  monitoring remains active; getfotty.com and direct email remain unavailable/OFF.
- The 4 November live campaign is expired. Its pending gates are historical, not authority for a new recurring check. Use fresh eligible fixtures and current owner authority; never reuse ended match pins. History: testing/fotty187-broadcast-reliability/ and fotty-resilience-2026-10-29/.

Audit:audit/Fotty-November-2026-Baseline.md.

## TV history 206–212

PR114/115 guides deployed; SkyCS1/beINTV17 holds and distinct CBS/Fubo/WillowSports failures: testing/fotty-tv-{expansion,recovery,next}-2026-10-31/.

## Cricket matching213/214 and Fox215

PR116/8298f54 cricket repair deployed1Nov; exact identity/IANA/ordinal/period
guards persist. Fox215 HTTP prototype was unqualified and removed216. Jet214
Willow hold passed; programme/audio/source limits remain historical. Details:
testing/fotty-cricket-matching-2026-11-01/ and Decisions-Log.

## 1 November broadcast history

217–219 added late alternatives, fresh TV discovery, bounded renewal and isolation of regressing rows without renewed leases. Jet Juventus TV4 passed a correct-programme 90-second hold. Willow TV1 alternated between decoded video and HTTP 404 while CS decoded; a later HLS response did not establish recovery. EFL empty-window repair remained local. See audit/Fotty-November-2026-Baseline.md, testing/fotty-liverpool-watch-2026-11-01/ and Decisions-Log.md for individual receipts.

## Watch feedback, fallback and Retry220 history

Pending/Cancel feedback, same-player resume, bounded fallback and fresh Retry
receipts are in [the 220 record](../testing/fotty-watch-retry-2026-11-01/README.md)
and Decisions-Log. Its physical gaps are dated evidence; current qualification
is the build332 receipt above. Preserve owner/attempt/intent/background fences.

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
