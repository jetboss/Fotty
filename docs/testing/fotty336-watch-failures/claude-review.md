# Watch failure repairs — independent review

15 November 2026. Actual Claude performed three bounded, read-only reviews of
frozen source and redacted evidence through the existing local review bridge.
Each response completed successfully with exit code 0 and no permission
denials. Claude did not run builds or tests, operate devices, fetch provider
data, or implement the repairs. The summaries below preserve the changing
evidence and the earlier blocker; they are not a blanket playback qualification.

The source baseline was `e98f3a014b0399cab18e9b81b4402d6d5860981b`.
Ranking formulas/order, source admission and programme guards, recovery budgets,
phone and TestFlight were outside the repair scope.

## Round 1 — diagnosis with incomplete playback records

Claude could not establish a production cause for the two no-stream outcomes or
the original Belarus–Albania buffering sample from the initial exported subset.
It distinguished a resolver failure from the coordinator rejecting otherwise
successful results, and noted that `provider_returned_empty` can mean no exact
fixture, an empty descriptor, rejected deliveries, or final admission filtering.
That category does not establish that every provider returned an empty array.

It identified pre-existing diagnostic flaws: a checked-empty sibling could hide
an actionable security failure; final admission rejection could be described as
an empty result; and optional discovery records could use the generic `single`
route. It also noted duplicate failure accounting and missing correlation fields.
These were not presented as proven causes of missing match supply. Only the
focused classification repair was selected for this gate; the other diagnostic
observations were not silently folded into the implementation.

The reviewer requested existing per-provider failure/admission evidence before
changing supply or recovery. The original 28-second buffering observation ended
with a manual close and one failover. It did not establish that a replacement's
startup budget had expired.

Two overly strong inferences in that first response were explicitly corrected
and accepted in round 2: the category alone does not prove all failures were
definitive misses, and elapsed time below the collection deadline does not prove
all lanes completed because the collector also has an early grace exit.

## Round 2 — Highfly accepted; aggregate Retry blocker found

Frozen four-file patch SHA-256:
`2b2636362db088e3e74d504e44507536f52205eecdef7a77faf5319f7ed00794`.

Claude approved the Highfly repair: a missing fixture after an incomplete catalog
read is treated as unconfirmed; a fully read empty catalog remains a definitive
miss. Existing conflicting-identity vetoes, successful fallback behavior and
team/date/squad and delivery checks remain intact. It noted a non-blocking
diagnostic limitation: the existing invalid-response category is less specific
than the underlying incomplete-catalog condition.

It blocked the first shared classifier change. `providerSecurityFailure` also
represents rejected unsafe metadata/descriptors, whose individual retry flag is
false. Returning that failure for `[empty sibling, unsafe descriptor]` would
remove aggregate Retry, preventing a fresh check of the other sources. That was
a concrete regression in the proposed repair, not a reason to weaken the safety
check or retry the rejected descriptor.

The reviewer required real unsafe-response and TLS test inputs. The subsequent
correction filters account failures and explicitly tagged TLS failures before
applying the existing failure priority. Unsafe descriptor plus an empty sibling
retains the existing partial result and aggregate Retry; unsafe-only handling
remains unchanged. Tests cover both input orders and an unsafe error preceding
the actionable account/TLS cause.

Fresh [Jet diagnostics](jet335-diagnostics.json) showed provider matching misses
for Suriname, not proof of hidden playable deliveries. The separate
[Belarus reproduction](jet335-belarus-reproduction.json) showed HF2 technically
starting but displaying basketball. Claude kept programme correctness separate
from startup success and did not recommend banning unparseable labels or
changing ranking.

## Round 3 — all three repairs approved at source level

Frozen seven-file patch SHA-256:
`c78db0a68b198b9e149ce36ce8f2a0975368870568abd81e31801a4c4834d7a0`.

Claude's final verdict: **all three repairs cleared at source level, with no
blockers**. The earlier aggregate Retry blocker was closed. The Highfly repair
remained approved.

The newly available [redacted hang evidence](jet335-hang.json), combined with
source, established an application lock inversion for the later watchdog kill:

1. Main was waiting for the health-store queue inside `recordSuccess`.
2. That queue was persisting programme evidence to UserDefaults while serialized.
3. Synchronous defaults notification delivery waited for a main-queue observer.

The persistence repair reuses `FottyDefaultsWriteBuffer`. Health mutation and
enqueue remain serialized, but draining occurs after releasing the health
queue. Pending values are visible to reentrant reads. The review covered
programme/match evidence, health snapshots, last-good provider, migration,
reset, lazy initialization and write ordering. No ranking formulas or
comparators changed.

Claude also reviewed the isolated test suite and three reentry regressions:
metadata notification with nested successful-playback writes, reset followed by
fresh writes, and read-triggered migration preserving counters, timestamps and
ranking. The tests exercise the notification mechanism, not an integrated live
`SportsContinuityBridge` instance. The reviewer expressly conditioned final
validation on compilation, test results and physical nonrecurrence; it did not
claim those had passed.

This hang evidence pertains to the later 18:42 watchdog termination. It does not
retroactively attribute the original 17:57 buffering sample. None of the three
repairs proves new Suriname supply or fixes HF2's wrong programme.

## Subsequent test-only correction — Codex review

**Reviewer: Codex core-motion subagent, independently of Claude.** After Claude's
final frozen packet, `StorageRuntimeSafetyTests.swift` changed at three wait
sites and gained `waitForHealthWriters`. No production file changed in this
correction. It was **not included in Claude round 3** and no additional Claude
review is claimed.

The previous five-second test wait could return after a timeout while a global
worker was still running. The surrounding isolated-store scope could then
restore the shared state before that worker finished. The corrected helper
requires `XCTWaiter.Result.completed`; otherwise it records a failure and
terminates the hosted test process before the scope can unwind. Each worker
signals completion only after its store operation and synchronous notification
delivery return. The first test also requires its observer expectation.

Codex reviewed the exact four-hunk post-review diff and found no blocker. This
closes the test-lifetime failure path without changing production behavior or
loosening assertions. The deliberate trade-off is a hosted test-process failure
if the worker cannot finish, instead of allowing unsafe continuation. The
coordinator must compile and rerun the final test source; results from the earlier
in-flight suite cannot qualify this changed test file.

`StorageRuntimeSafetyTests.swift` SHA-256 in Claude's frozen packet:
`962f00fd2fa45a95b4d9ff656a0fcfdac183ebf92812745e984eea0417268843`.

SHA-256 after the Codex-reviewed join guard:
`4f759d6108c581cbc66aa51d067ebb68c182e625908c9c26e1e862e58c8a0ede`.

Final compilation, test totals and physical results belong in the coordinator's
validation receipts. This document records review decisions only; it contains
no private session identifiers, account material, raw crash report or tool history.
