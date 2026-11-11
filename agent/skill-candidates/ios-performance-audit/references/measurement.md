# Bounded measurement workflow

## Define the interval before capture

Choose the smallest reproduction that distinguishes the suspected causes.
Examples: first cold catalog scroll, returning to a warm tab, tap-to-visible
acknowledgment, source lookup, player preparation or resize at large text.

Record source receipt/build, device/window, OS, explicit developer directory,
configuration and dataset/cache state. Note thermal/power state and network
conditions when they could change the result. Test ordinary workload separately
from an intentionally stressed workload. An old desktop app is not a baseline
for a new phone build.

Use an optimized device configuration for tester-equivalent performance when
authorized; a Debug run can still diagnose a defect, but does not establish the
same cost as Release. Keep cold and warm intervals separate.

## Capture only what the request permits

Inspect existing helpers before running them. Some “performance gates” also build,
sign, register a device, install, terminate or launch an app. A valid device ID
does not authorize these actions. Select a capture-only path for an already
installed approved build when suitable; otherwise leave the required gate open.

Prefer current app-scoped Instruments capture, with SwiftUI update timing plus
Time Profiler and Hangs/Hitches where supported. For a non-SwiftUI hang, inspect
the relevant CPU, wait, decoding or networking evidence instead. Verify installed
templates and export schemas; do not hardcode commands or schema names from an
unverified version. Use current Apple documentation when the workflow changes.

Take a short bounded capture sufficient for the interaction. Use one task-owned
temporary directory and a cleanup trap or equivalent finally block. Check storage
before and after heavy work; remove only owned builds, traces, screenshots and
exports after analysis or interruption. Preserve a small redacted summary if
needed, not duplicate raw recordings. Do not inspect unrelated apps or collect
system-wide traces without appropriate scope and authority.

If tool or device access is unavailable, complete safe source analysis and name
the smallest missing evidence. Request manual capture only when agent-operated
capture or navigation is genuinely unavailable or requires user-only interaction.

## Analyze the interaction, not merely the file

Identify the problematic time range. Correlate long view/representable updates,
main-thread stacks, update causes, image work or waits with the actual symptom.
Body counts or highlighted updates alone do not prove a hitch; launch preparation
and scrolling have different contexts. A trace table of contents shows available
schemas, not performance acceptance.

For delayed Watch or similar actions, separate input handling, first visible
feedback, source resolution and first decoded frame. Signposts can delimit code
intervals but a signpost/state assignment alone cannot prove visible feedback.
Use render/interaction evidence for that claim. Do not blame provider latency on
the UI without a correlated blocked interaction.

## Compare and report honestly

Repeat the same interaction with comparable conditions and enough observations
to expose ordinary variance; choose the count proportionately rather than mandate
a large fixed run. Report counts, units, measurement method and missing data.
Do not infer a meaningful improvement from mismatched device/configuration,
cold-versus-warm runs or different datasets. Unknown values are not zero.

Use CPU, memory, hitch/hang and latency measures that answer the actual question.
For supplied timing samples, a median may summarize the sample; label small-sample
tails and do not invent a reliable percentile. A lower mean is not success if
worst-case freezes, correctness, playback continuity or memory grow worse.

A comparable measured improvement is narrower than broad user acceptance.
Separate source checked, tests passed, trace captured, measured comparison and
physical/owner acceptance. A capture/build can succeed while responsiveness
remains unverified. Synthetic evaluation data never qualifies a production app.
