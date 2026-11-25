# Fotty adapter for reusable iOS skill candidates

The owner approved reusable iOS skill upgrades on 2026-10-03. Their portable
copies were staged in agent/skill-candidates under that session's read-only
personal-directory constraint. Staging is not global discovery or activation;
check current permissions and explicit activation scope instead of carrying
that historical access restriction into a new session.

## Task routing

- Native design/reference handoff: use the available apple-ui-design skill and
  read agent/skill-candidates/apple-ui-design/references/native-handoff.md for a
  substantial handoff. The candidate preserves its existing baseline and adds
  that focused reference. Fotty’s design standard remains product authority.
  The active resource/evidence workflow is docs/design/UI-Reference-Workflow.md;
  check tools/check-ui-design-evidence.mjs before declaring a core UI handoff
  complete. Component evidence cannot close a whole-screen/device gate.
- Hangs, cold-scroll stutter, delayed tap feedback or memory pressure: read
  agent/skill-candidates/ios-performance-audit/SKILL.md and its applicable
  references. This is not an automatic build or installation request.
- Playback correctness: use agent/playbooks/playback.md to establish media and
  attempt ownership. Performance work must not guess the playing owner or
  rewrite PiP, source admission or recovery during presentation polish.
- Backend/fixture work alone does not activate native design/performance guidance.
  Improving these instructions does not authorize app/FPL/backend changes.

## Existing tools, not another framework

Inspect tools/ios-performance-gate.sh before any future authorized use: it
builds/signs, may update provisioning, installs, terminates/launches the app and
optionally captures a trace. Its schema listing and “passed” label do not evaluate
responsiveness. Do not invoke it for a read-only or source-only task. The script
itself is unchanged in this skill upgrade.

Pin the verified official developer directory from Current-State.md, not the
legacy helper’s beta fallback. Verify the named physical device and permitted
actions first. Respect 256 GB / 8 GB limits, no simulators, sequential heavy
builds and cleanup of one owned temporary output directory.

Reuse current unit/contract tests, MetricKit/signposts and the project’s existing
UI/performance tools. Source and Catalyst evidence remain narrower than physical
phone/iPad interaction. Retain a redacted measurement summary, not unbounded
traces. No provider URLs, account data or secrets in the skill/evaluation pack.

## Evaluation and activation

The small cases in agent/skill-evals/ios-cases.json test routing, authority,
correctness and evidence claims using synthetic fixtures. Do not read a case’s
grading criteria into the evaluating agent’s prompt. Give it the request, skill
and minimum supplied inputs; grade the answer afterward. Manifest checks are
structural, not proof of behavior or app performance.

Before explicitly requested global activation, check actual write access and
validate the portable candidates again. Preserve unrelated skills; review the
existing personal Apple skill before replacement. Do not bypass filesystem
boundaries. Activation is separate from project guidance and local tests; the
25October resource/evidence workflow does not install or replace global skills.
