# Fotty — daily-use evidence and next product phase

Current execution order: the owner approved the broader
[private product execution plan](FOTTY-PRODUCT-EXECUTION-PLAN.md) on 4 September
2026. Use that document for new work. The dated milestones below are historical
context and must not override current release records or restore retired code.

Approved: 28 August 2026. This is the execution order accepted after the
product-gap discussion, not a claim that every phase is complete.

## Outcome and boundaries

Make the existing multi-sport watch experience dependable, and make the dedicated
FPL workspace earn trust through verified facts and useful, testable advice.
Preserve badges, compact rows, optional appearance, provider-owned controls,
Home discovery and personal My Matchday. No broad redesign is part of this pass.

Fotty is a private, invite-only product. Normal shared releases use the existing
internal TestFlight group; an explicitly authorized private cable build may be
used for a narrow physical check. Public App Store distribution and external
TestFlight are not active product goals. No new testers, account roles, paid
service, official FPL transaction, Git publication or name change is implied.
No simulators; sequential builds and bounded cleanup.

## Current 2.0 qualification direction — approved 31 August 2026

Discovery and truthful playback are Fotty's universal promise. FPL remains a
first-class optional power tool: Gameweek, Squad and Coach are primary, while
Tools is secondary and labels official facts, projections, estimates, published
data, on-device plans and advanced solvers explicitly.

The unreachable community/chat/profile, old insights/highlights, mock-match and
debug-validation surfaces are retired from the production graph. Compatibility
model metadata remains temporarily so existing private SwiftData stores stay
readable. The checked-in iOS/iPadOS 26.4 minimum is intentional for this private
cycle and must not be broadened without real older-device qualification.

The next expansion is limited to 3–5 trusted testers for one seven-day daily-use
qualification after the exact candidate closes its physical and backend-identity
entry gates. The complete protocol is
[`docs/beta/PRIVATE-QUALIFICATION-2.0.md`](beta/PRIVATE-QUALIFICATION-2.0.md).

## 1. Ship and qualify the reliability patch — superseded by build 45; physical acceptance open

Internal TestFlight release: **2.0.0 (43)**. Scope: the five already implemented
playback/scoring/Coach request fixes, not additional product features.

Automated qualification, Worker deployment and Apple upload/processing are
complete. The owner-approved declaration, notes and existing-group assignment
are saved. Apple independently shows **Internal / Testing** for the unchanged
two-tester group at **2026-08-28 12:47 AST**; exact-build human acceptance remains open.

- Recheck live Apple build numbers, allocate once and preserve source identity.
- Run full units, focused changed-surface UI checks, web/Worker contracts,
  production web build, normal signed archive and Review Safe compilation.
- Deploy the matching Worker, record its previous revision, and smoke-test
  health, request rejection and zero-token unknown-scoring behavior.
- Verify upload, processing and existing-group availability independently.
- Then qualify the exact TestFlight build on supported iPhone and iPad.

Authority: [release record](releases/Fotty-2.0.0-43.md),
[release process](RELEASE-PROCESS.md),
[round-one acceptance](beta/ROUND-01-ACCEPTANCE.md).

The current shared round advanced to **2.0.0 (45)** on 29 August, consolidating
the private FPL draft fix, Coach lifetime guard, current-season reference-data
remediation and StoreKit distribution migration. Apple independently shows 45
Internal / Testing for Fotty Internal Smoke with two invitations; use
[the build-45 release record](releases/Fotty-2.0.0-45.md) and record new human
acceptance against 45 rather than treating build-43 installations as current.

The initial Apple preflight shows both existing testers installed build 42.
Build-list metric cells remain dashes, and Screenshot Feedback reports none.
These observations do not establish zero crashes, zero sessions or report delivery.

## 2. Observe a fresh tester round — awaiting exact-build acceptance

First use the existing group to verify physical playback, retained data and one
received TestFlight report. Then the owner selects a qualification group of
3–5 trusted testers, including differing screen sizes and FPL experience.
Do not invite people or expand their permissions without specific authorization.

Give outcomes, not directions to the right buttons. Record whether each task
was completed independently, needed help, failed, was blocked by a provider,
or was not attempted. Keep app errors distinct from provider availability.
Investigate every wrong-total, lost-data, hidden-audio or unusable-control report
before prioritizing cosmetic preferences. Use TestFlight and opt-in local
diagnostics; no new background analytics service is required for this round.

## 3. Improve data and Coach confidence — next implementation phase

The first pass hardens Coach request ownership, consent/cancellation, context
changes, factual recovery and direct current-score wording. Its iOS work is in
internal TestFlight build 45; see the [conversation-integrity record](audit/Fotty-Coach-Conversation-Reliability-2026-08-28.md).
This does not complete strategic-model evaluation or the physical tester round.

- Reproduce catalog alias/time mismatches before changing identity. Never merge
  doubleheaders, attach a channel by league name, or erase saved intent because
  a provider temporarily omits an event.
- Preserve scheduled/listed/decoded/score-checked distinctions. Recheck the dated
  CPL snapshot before releases; do not silently turn it into a live feed.
- Extend Coach evaluation beyond schema checks: follow-ups, missing facts,
  conflicting client context, manager/gameweek changes and alternative plans.
  [Acceptance cases](beta/COACH-ACCEPTANCE-CASES.md) define the next evaluation.
- Retain deterministic scoring, freshness and consent. DeepSeek remains the
  reasoning path for strategy; passing an offline test does not prove advice quality.
- Record versioned projections before the relevant deadline and compare with
  later outcomes. Do not retrospectively fill predictions from final results or
  advertise a measured FPL advantage before sufficient evidence exists.

Exit: reproduced defects have regressions; accepted advice states its evidence,
uncertainty and actions; unknown totals stay unknown; no hindsight leakage.

## 4. Compatibility and recovery — encrypted backup implemented; physical acceptance open

- The distributed minimum remains iOS/iPadOS 26.4. A lower-target compile probe
  is diagnostic only. The unchanged normal Release app/extension pass an iOS 18
  compile probe; [the assessment](audit/Fotty-Device-Compatibility-2026-08-28.md)
  identifies the required older-device and Review Safe checks. No support promise
  changes until those pass.
- A versioned, previewable, password-encrypted backup/restore workflow now
  transfers preferences, follows, saved Matchday identity and manager-scoped
  local FPL plans. It excludes credentials, Coach conversations, cached provider
  URLs/source identifiers, consent grants, reminders and diagnostics. Restore
  validates the complete payload before mutation, replaces only the documented
  state, clears AI consent and leaves reminders off. Four focused regressions
  and the complete simulator-free iOS CI gate pass. Files-app export/import and
  a real-device restore remain human acceptance, not inferred evidence.
- Optional sync follows only if the backup workflow and tester demand justify
  its account, privacy, conflict resolution and operating costs.

## 5. Personalization and operations — after round-one evidence

- Consider optional favourite-sport ordering while keeping All sports visible.
  No extra destination, duplicate Home or FPL promotion outside its workspace.
- Define per-tester/day and global Coach allowances, concurrency protection,
  emergency disable and recovery behavior. Current request limits are not a
  hard monetary ceiling; select a real budget with the owner before enforcing it.
- Document provider/score failure triage and rollback. Keep diagnostics off
  the media-segment path and redact all shared evidence.
- Background match updates require a separate service design. Local reminders
  cannot discover a reschedule while Fotty is closed; better copy cannot change
  that architectural limit.

## 6. Private distribution and identity — owner decision recorded

The working promise is broad sports discovery/watch with a particularly strong
FPL companion. Evaluate a new name against that promise; do not rename binaries,
bundle IDs, domains or Apple listings until one is selected.

The owner decided on 30 August 2026 that Fotty stays private. Keep access
invite-only through the internal group or an explicitly authorized private
device build. Do not spend product time on public-review workarounds, disguise
functionality, create an external group or submit publicly unless the owner
later makes a new explicit decision. Internal distribution still does not prove
authorization for third-party content; provider limitations remain visible.

## Definition of progress

Keep implementation, automated qualification, deployed service, Apple upload,
tester availability, installation and real user acceptance as separate states.
Human-only checks remain open until someone actually performs them. The next
phase is not complete just because its checklist or tests have been written.
