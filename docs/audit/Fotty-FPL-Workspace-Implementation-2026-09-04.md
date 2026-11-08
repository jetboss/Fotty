# FPL workspace — implementation record

4 September 2026 · private local source after build 58

## Outcome and qualification status

Batch 3 of the [product execution plan](../FOTTY-PRODUCT-EXECUTION-PLAN.md)
extends the FPL trust boundary beyond the main score: Rival Race, player history,
season identity, planning windows and Coach now use more explicit evidence and
ownership rules. It addresses the code-level gaps in whole-product audit
findings 9–10 without adding another tool destination or applying official team
changes.

The final complete `cd web && npm run test:unit` gate passed **135 of 135 tests**,
with zero failures. The package script explicitly includes the new Coach
evidence and transfer-validation modules; this is not only an isolated helper
run. The final Mac Catalyst test pass completed **481 tests with zero failures**
and two intentional live-provider/soak skips (483 total). The generic unsigned
iOS Release build also passed. **This batch is locally qualified**, not physically
accepted or deployed.

This is not a release or physical-device acceptance record. Build/version and
distribution remain unchanged: the source build number stays 58, and this batch
is not an installed artifact. No app/Worker deployment, paid model request or account mutation was
performed. Checked-in Coach configuration remains paid disabled with a maximum
of 50 paid attempts per UTC day for the whole private group when separately
enabled; deterministic local answers do not spend that allowance.

## Implemented changes

### 1. Rival Race shares the accepted scoring snapshot

`FPLRivalSnapshot.swift` combines one accepted own-team packet with the selected
rival's published picks. Both teams use the same bootstrap, gameweek, fixtures,
event-live data and deterministic autosub/finality rules. The selected rival is
recomputed as primary evidence changes; there is no independent rival live-feed
poller or use of a local draft as the manager's published scoring lineup.

Endpoint identity, gameweek, manager/rival identity, receipt age and complete
player-level evidence are checked before publication. Rival picks must be
current within the bounded freshness window, and the displayed receipt is the
oldest contributing resource rather than the end of the latest request. A
failed refresh retains the last complete comparison with an explicit failure or
stale state. A different selection, season or primary revision cannot receive
an old request's result. Pre-deadline private rival squads are not fabricated.

### 2. Player evidence and manager identity cannot silently cross boundaries

Native player-history reuse has a five-minute receipt policy; a disk snapshot
is not a current official check. Same-identity in-flight work coalesces, forced
refresh replaces owned work, and player selection/manager/season changes cancel
or reject obsolete publications. Endpoint mismatch and regressing receipt times
cannot replace the selected player's evidence. Comparison selections have
explicit refresh, age and error states; a failed update preserves readable
previous history without giving it a new receipt.

`FPLManagerSeasonStore` requires an explicit previewed Connect confirmation for
the manager and current season. A saved numeric entry ID is not proof of the
same team after rollover. Pending confirmation blocks stale workspace actions
and late replies. Existing correctly scoped plans/history remain stored.
Unscoped legacy draft/chat bytes are quarantined rather than assigned to reused
current player IDs or deleted: confirming a team cannot establish those bytes'
original owner or season.

### 3. Planning tools respect current windows and complete inputs

`FPLPlanningBounds` clamps horizons to actual published gameweeks and stops at a
missing calendar entry; it does not invent GW39 or shift later evidence into an
earlier slot. Journal writes use an explicit intended planning gameweek, with
current-season/manager checks, instead of silently attributing a future decision
to the live gameweek.

`FPLChipAvailabilityPolicy` separates within-window, used, later, expired,
deadline-passed, blocked and unknown states. Official bootstrap allocations own
the windows. Public usage, opening-gameweek restrictions, one-chip-per-gameweek
and consecutive Free Hit restrictions are checked. Unknown season rules or
missing manager history yield a check-in-FPL state, not an AVAILABLE promise.
The supplementary constraints were checked against the Premier League's
[2026/27 chip announcement](https://www.premierleague.com/en/news/4679879) and
[official chip guide](https://www.premierleague.com/en/news/2174900). Published
windows still do not disclose a manager's pending private activation.

Automatic and manual wildcard generation use the same modeled starting-budget
policy. Published values/bank, local saved budgets and initial-rule fallback
remain distinguishable assumptions. Same-count optimizer replacements are
identified by content, not array count. Constrained working results can remain
visible after evidence changes, but become stale and cannot be saved as current
until refreshed. Locks, exclusions and unfinished plans are not erased merely
to refresh the display. Labels distinguish players still involved from an
actual count of remaining fixtures, including doubles.

### 4. Coach checks named subjects and qualifies strategic assurance

`coach-evidence.mjs` resolves exact current-bootstrap aliases, including
diacritics, hyphens and possessives, before selecting evidence. A named player
outside the recommendation/top-projection shortlist is included by official ID.
Ambiguous names can use explicit club context; unresolved names receive a
clarification rather than a guessed popular player. Singular/plural follow-ups
use the immediate previous user subject, not an assistant's invented facts or
an unrelated older topic. Explicit client/official identity conflicts remain
visible and current official identity takes precedence.

There are at most eight named subjects and four detailed player-history fetches,
with two in flight and a four-second history budget inside the existing
50-second request deadline. Completed histories survive a sibling timeout;
missing history stays unknown, not zero minutes or injury certainty. Detected
ambiguity/missing identities return before reserving a paid attempt. Exact name
matching is conservative, not a universal natural-language recognition claim.

The native cards now say Evidence cited by Coach and identify model confidence
as judgment, not measured accuracy. Evidence receipt time does not certify every
generated claim. Recheck with current evidence submits the historical user's
question, preserving its immediate user context for pronouns, and creates a new
dated answer; it does not rewrite historical advice. The composer remains usable
with cloud consent off, but only deterministic on-device facts or an explicit
cloud-off response may run in that state. Cloud strategy remains opt-in.

### 5. Structured routes have a bounded, whole-squad check

Strategic output may optionally include `proposedTransfers: [{out, in}]` with
official integer IDs. `coach-transfers.mjs` evaluates all pairs together against
the current full catalog, kept server-side rather than expanding the model
packet. Checks include a complete distinct 15-player baseline/result, owned
outgoing players, no duplicate/already-owned incoming players, no buy/sell cycle,
selectability, same-position replacement, position quotas and the club limit.

Combined affordability uses an explicitly identified bank/value estimate.
Missing selling values may use current catalog prices only as a labeled
estimate; private purchase history is never reconstructed. The **adjusted bank
for a local draft is not currently supplied to Coach and remains unknown**,
rather than borrowing the published pre-draft bank. Passing public estimates is
conditional, not authenticated-account proof. Missing structured IDs or unknown
budget leave the route unverified; prose is never parsed into moves.

An illegal structured proposal is withheld with a safe explanation and consumed
usage recorded; it does not trigger an automatic paid retry. Nothing applies a
plan. Free-transfer allowances, hit costs, private selling prices, future
minutes and all unstructured model claims still require appropriate evidence
and user checks before any official action.

### 6. Transfer hits are deducted exactly once

Native and Worker scoring preserve the published gameweek-points field as the
raw official observation and derive a separately labeled net contribution.
When raw points are unavailable, a player-derived net fallback is not netted
again. Safe pending autosubs, data-checked/final states and Rival Race comparisons
use consistent bases. This avoids comparing one side before hits with the other
after hits, or deducting a hit twice. Deterministic factual answers distinguish
published points, net contribution and provisional substitutions rather than
asking a model to repair arithmetic.

Native summary fields explicitly distinguish `officialPointsBeforeTransfers`
from `officialNetPoints`; the old fallback-bearing field remains compatible.
The UI compares net with projected net: published 50 minus a 4-point hit is 46,
so a projected 59 is a +13 rules adjustment, not +9. Derived-only and incomplete
snapshots identify their basis, and a negative change is not styled as a gain.
Native and Worker direct-total question routing share the same bounded contract,
with explicit future/historical wording excluded from current-score answers.

The semantic reference is the [official FPL Help/FAQ](https://fantasy.premierleague.com/help):
the FAQ distinguishes summed gameweek scores from season totals after transfer
deductions, and the head-to-head rule subtracts transfer points from the gameweek
score. Because Help is JavaScript-rendered, the team verified that text and the
separate points/transfer-cost display in the current official frontend bundle
([official frontend bundle](https://fantasy.premierleague.com/assets/index-DI-BMj2h.js))
on 4 September. This is official client/rule evidence, not a claimed empirical
nonzero-hit sample: the bounded sanitized sample entries inspected had zero
transfer cost.

## Verification record

| Gate or coverage | Result for this batch |
| --- | --- |
| Full web/Worker `npm run test:unit` | 135/135 passed; zero failures |
| Worker packaging dry-run | Final source passed; 109.61 KiB / 30.04 KiB gzip; paid flag 0, daily limit 50; no deployment |
| Coach evidence/route corpus | Included in the full gate: rare/ambiguous/missing names, pronouns, conflicting context, history budgets/cancellation, combined club/budget failures, ownership/position negatives and no automatic paid retry |
| Native behavioral coverage | Added/updated `FPLMatchdayRefreshTests`, `FPLRivalSnapshotTests`, `FPLPlanningBoundariesTests`, `FPLCoachEvidenceTests` and relevant trust/plan/navigation tests; 481 passed |
| Native compilation/test gate | Catalyst: 483 total, 481 passed, 0 failed, 2 intentional live/soak skips. Generic unsigned iOS Release passed. |
| Resource cleanup | One reused disposable root; sequential builds with two jobs, no simulators. All owned native/Worker output removed; about 30 GiB free afterward. |
| Focused source checks | Changed Coach Swift syntax parsing and scoped diff checks passed; these do not substitute for native typechecking/runtime tests |
| Paid/live model and physical-device evaluation | Not performed; open acceptance work |

## Remaining acceptance and limits

- The combined gate used Xcode 27 beta, with only the Catalyst test target
  overridden to 26.0; the generic iOS Release kept the real project deployment
  target. Earlier runs exposed incomplete synthetic calendar fixtures and a
  direct-total routing gap; these were fixed, not waived. Older navigation/chat
  tests now load a current workspace and also assert that premature requests are
  blocked. The final gate covers the resulting source, including net-score and
  rollover regression fixes. No prior passing total was substituted.
- On one approved exact iPhone/iPad candidate, verify rival refresh/finality,
  retained planning edits, history recovery, season confirmation, chip-window
  states, same-count wildcard changes and target-gameweek journal saves.
- Exercise Coach consent-off facts, opt-in strategy, history/recheck and large
  text/VoiceOver on device. Offline response fixtures are not measured live model
  accuracy, latency, usability or a guarantee of winning an FPL league.
- Run any paid evaluation only with separately authorized allowance. Current
  source configuration is not evidence of deployed backend configuration.
- Preserve unknown draft bank/private facts and distinguish conditional route
  checks from model prose. No automatic official transfers, new accounts,
  deployment, version bump or wider tester distribution is included here.
