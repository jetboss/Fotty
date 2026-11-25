---
name: ios-performance-audit
description: Diagnose iOS and iPadOS hangs, scrolling hitches, delayed interaction and memory pressure using code and measured evidence. Not a visual redesign or an automatic release gate.
---

# iOS Performance Audit

Identify the expensive work or blocked interaction without trading correctness
for speed. Use existing project instrumentation and tests before introducing
another framework. Audit means findings; implement only a requested scoped repair.

## Select the investigation

- Recover the exact interaction, affected source/build/device/OS, configuration,
  dataset and relevant conditions from available context. Ask only for missing
  evidence that changes the diagnosis.
- Distinguish tap acknowledgment, source/network lookup, player preparation and
  first visible media. A slow provider does not prove SwiftUI is blocked, and an
  immediate spinner does not prove playback is healthy.
- Read the relevant code and ownership boundary. Check observation fan-out,
  stable identity, repeated derived work, layout feedback, image decoding, actor
  isolation and lifecycle tasks. Rank concrete failure scenarios over generic
  stylistic smells. Leave correct code unchanged.
- Use [Correctness checks](references/correctness-checks.md) when evaluating
  caching, equality, asynchronous work or media-related optimization.
- When code cannot establish the runtime cause or a responsiveness claim needs
  proof, use [Measurement](references/measurement.md). Code review may continue
  while device access is unavailable; do not fabricate trace-backed findings.

## Work within the actual environment

Inspect project instructions and any local performance adapter before running
tools. Verify the tool’s side effects, current toolchain and named target.
Prefer authorized agent-operated capture and navigation when the tools support
them; do not make the user perform steps the agent can safely do.

Building, installing, launching and collecting traces are distinct actions.
Do not run a combined install script for a source-only or read-only request.
Honor workstation limits, including a no-simulator rule when supplied. Use one
bounded owned output directory, sequential heavy builds and cleanup on every
outcome. Keep user data, pre-existing caches and other tasks’ output intact.

## Diagnose, repair and compare

Separate static defects, code-level performance hypotheses and measured runtime
bottlenecks. Correlate a problematic interval with relevant stacks or SwiftUI
update causes, rather than selecting the largest counter anywhere in a trace.

For an authorized fix, preserve input freshness, first-load behavior, identity,
cancellation and ownership. Run affected correctness checks before comparing
the same interaction against its baseline. Do not recommend blanket equality
wrappers, Observation migrations or actor changes without evidence.

A successful build, process hold, exported trace or schema list is not a
performance pass. Report a measured delta only for comparable evidence, with
sample size and material caveats. Missing or confounded measurements leave
responsiveness acceptance open; they do not force unrelated work or release.

## Handoff

Give the confirmed problem, downstream impact and focused remedy; distinguish
hypotheses and unverified checks. Record the evidence identity and the next
specific measurement if needed. Open current Apple guidance for material tool/API
decisions using the [source routing](references/apple-performance-sources.md).
Do not imply that this skill, a benchmark or local tests qualify an entire app.
