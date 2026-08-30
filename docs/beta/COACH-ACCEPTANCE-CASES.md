# Coach acceptance beyond arithmetic

Status: **next-phase evaluation specification; not a completed model evaluation**.

The 28 August Unreleased conversation-integrity pass adds offline evidence for
clear/disable cancellation, old/new manager replies, context changes, follow-up
history transport and factual fallback. It also catches direct current-score
phrasing. See [the test record](../audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md).
Preserving “Why?” in the request history does not prove the live model explains
the same decision well; that strategic-quality case remains open.

Run offline routing/data cases first. Use only consented, minimized synthetic or
owner-approved context for a separately budgeted live-model pass. Never put
actual manager IDs, private conversation history or provider keys in this file.

For each answer, capture source/model, verified data time, gameweek, evidence,
limits, recommended action and returned token usage. Facts must be checked
against the evidence supplied at that moment, not later match outcomes.

| Case | Required behavior |
| --- | --- |
| Known keeper and legal outfield autosubs | Rules path gives supported official/provisional totals and names eligible replacements; zero model tokens. |
| Missing, duplicate or invalid live rows | Unknown is not zero minutes; no unproven autosubs or derived total. |
| Old picks or gameweek change | Refuse a current total from the previous gameweek; refresh or explain the gap. |
| Published final total contradicts client draft | Official checked data wins; a draft is not an official transaction. |
| Captain absent, vice appears; Triple Captain | Explain the verified multiplier without asking the model to calculate it. |
| Double-gameweek player has another fixture | No premature confirmed non-appearance or substitution. |
| “Why?” after a transfer recommendation | Explain the same decision and evidence; do not start unrelated advice. |
| “What if he only plays 20 minutes?” | Treat this as an explicit scenario assumption, not a new verified availability fact. |
| “What changes if I take a four-point hit?” | Compare net tradeoffs using a legal plan, horizon and stated assumptions; no guaranteed gain. |
| Missing exact selling price/free-transfer balance | Identify public-data limits; ask for the missing fact or show a bounded assumption. |
| Manager switched during a pending question | No old-manager reply, draft or score may enter the new manager's workspace. |
| Conflicting user claim versus official evidence | Explain the discrepancy respectfully with source and time; do not simply agree. |
| Official service fails during tactical advice | State evidence limits and avoid current factual certainty; scoring still stays deterministic. |
| Provider timeout, malformed output or request limit | Clear recoverable state; no silent invented answer or duplicate paid retry. |
| Normal transfer/captain strategy | Useful alternatives, downside and next check; DeepSeek remains available with consent. |

Build 43's existing automated tests cover several scoring/request cases, not
every conversation or strategic-quality case above. A response passing JSON
validation is not proof that its recommendation is sound. Record failures before
editing prompts or the intent classifier; retain regression examples afterward.

Projection calibration is separate: record the model version, inputs, cutoff,
minutes assumption and prediction before the deadline, then score outcomes after
official finalization. Missing historical predictions cannot be backfilled from
the final result and presented as an honest backtest.
