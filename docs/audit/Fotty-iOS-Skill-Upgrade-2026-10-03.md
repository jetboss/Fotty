# Reusable iOS skill upgrade — 2026-10-03

## Outcome and activation boundary

The owner chose reusable iOS skills, with usability and performance as the
current priority. Two portable packages are prepared and evaluated:

- `agent/skill-candidates/apple-ui-design`: preserves the installed Apple UI
  skill and its dated baseline, adding a focused native-reference handoff.
- `agent/skill-candidates/ios-performance-audit`: an evidence-led companion for
  hangs, scrolling hitches, delayed feedback and memory pressure.

`agent/playbooks/ios-skills.md` separates portable guidance from Fotty-specific
tools, artwork, resource limits and playback ownership. AGENTS.md and
Current-State.md now route future Fotty work to it. Neither package is globally
installed: the personal skill directory is read-only in this session. Global
activation requires permitted access, a fresh check of the existing personal
copy and separately verified installation. No permission bypass was attempted.

No native app, FPL, backend or performance-helper code changed. No builds,
simulators, device actions, releases, deployments, commits or pushes occurred.
Bundled skill caches were not patched and no dependencies were installed.

## What the upgrade changes

The UI handoff now distinguishes approved identity from literal mockup geometry:
retain badges and sport artwork, compare equivalent native conditions, allow
accessible reflow, and leave visual/touch acceptance open without actual evidence.

The performance companion separates confirmed logic errors, runtime hypotheses
and measured bottlenecks. It checks first-load freshness, value equality,
cancellation and media ownership before proposing optimizations. A successful
build, trace export or helper's “passed” label is not a responsiveness result.
Comparable workloads and actual measurements are required for improvement claims.

Apple's [SwiftUI Instruments session](https://developer.apple.com/videos/play/wwdc2025/306/)
informs interval correlation and before/after investigation. The skill-creator
workflow and OpenAI's [skill evaluation guidance](https://developers.openai.com/blog/eval-skills)
informed behavioral trials, not just manifest validation. The existing UI baseline
was preserved, not represented as a fresh review of every HIG page.

## Behavioral evaluation

One task-scoped evaluator received the applicable complete skill, request and
minimum synthetic inputs, without reviewer criteria. The primary agent reviewed
each answer against `agent/skill-evals/ios-cases.json`. These are eight small
qualitative cases, not an automated benchmark, cross-model guarantee or app test.

| Case | Observed decision | Result |
| --- | --- | --- |
| UI discussion | Preserve identity; propose reflow; no invented screen proof or edits | Pass |
| Native handoff | Recognize artwork gap; accept possible accessibility adaptation | Pass |
| Row-cache audit | Identify initial empty cache and stale same-ID score; separate cost from correctness | Pass |
| Correct label subtree | Leave full-value equality and cheap projection unchanged | Pass |
| Capture-only log | Reject unmeasured “performance passed” claim | Pass |
| Confounded comparison | Reject improvement claim across different devices/workloads; memory remains unknown | Pass |
| PiP ownership | Do not substitute spinner changes for playback proof or guess the owner | Pass |
| Backend-only routing | Apply neither native skill | Pass |

## Structural and independent review

- Both packages pass the skill-creator validator; all four YAML files parse and
  invocation metadata matches their package names.
- Fifteen package/evaluation files checked; all five relative Markdown links and
  every fixture reference resolve. Eight case IDs are unique.
- Independent source review found two handoff defects: an ignored `.txt` fixture
  and missing entrypoint routing. The fixture is now `.md`; both routing links
  are added. Follow-up review verified both fixes with no remaining blocker.
- Packages, fixtures and adapter use approximately 80 KiB on disk. No temporary
  build products, traces or screenshots were created.

Future work should use these instructions on real scoped tasks, retain genuine
failures as new evaluation cases, and verify native results separately. Passing
this suite does not establish Fotty's present performance or visual quality.
