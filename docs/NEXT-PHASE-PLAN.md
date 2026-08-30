# Fotty — daily-use evidence and next product phase

Approved: 28 August 2026. This is the execution order accepted after the
product-gap discussion, not a claim that every phase is complete.

## Outcome and boundaries

Make the existing multi-sport watch experience dependable, and make the dedicated
FPL workspace earn trust through verified facts and useful, testable advice.
Preserve badges, compact rows, optional appearance, provider-owned controls,
Home discovery and personal My Matchday. No broad redesign is part of this pass.

Normal releases use the existing internal TestFlight group. No new testers,
account roles, external submission, paid service, official FPL transaction,
Git publication or name change is implied. The old local Git ancestry must
remain unpublished. No simulators; sequential builds and bounded cleanup.

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
received TestFlight report. Then the owner selects the next small group of
5–10 trusted testers, including differing screen sizes and FPL experience.
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

## 4. Compatibility and recovery — assess before changing the promise

- The distributed minimum remains iOS/iPadOS 26.4. A lower-target compile probe
  is diagnostic only. The unchanged normal Release app/extension pass an iOS 18
  compile probe; [the assessment](audit/Fotty-Device-Compatibility-2026-08-28.md)
  identifies the required older-device and Review Safe checks. No support promise
  changes until those pass.
- Start recovery with a versioned, previewable backup/restore design. Define
  exactly which preferences, follows, saves and manager-scoped plans transfer.
  Exclude credentials, cached provider URLs, consent grants and diagnostics by
  default. Validate before mutation, preserve the old state on failure, and
  never silently re-enable reminders or AI consent on another device.
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

## 6. Distribution and identity — owner decisions

The working promise is broad sports discovery/watch with a particularly strong
FPL companion. Evaluate a new name against that promise; do not rename binaries,
bundle IDs, domains or Apple listings until one is selected.

Before wider/public distribution, document permission for the relevant content
and services and select a supportable distribution path. An internal beta is not
proof of authorization or App Store acceptance. This is not an instruction to
purchase a licensing package, disguise functionality or submit externally.

## Definition of progress

Keep implementation, automated qualification, deployed service, Apple upload,
tester availability, installation and real user acceptance as separate states.
Human-only checks remain open until someone actually performs them. The next
phase is not complete just because its checklist or tests have been written.
