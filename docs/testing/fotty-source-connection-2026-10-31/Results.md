# Source connection gate — complete collection, incomplete source coverage

Owner corrected the repeated patch/build/test process. The earlier run was
interrupted at20:55UTC and remains separately recorded. The consolidated second
batch used one build, collected all eight enabled modules and completed at
21:17UTC. Collection completion does not mean every source plays. No new Watch
routing or TestFlight release was performed. The subsequent missing-Watch
incident below required a separately owner-approved focused backend deployment.

## Confirmed findings and repair status

| Area | Evidence | Current status |
| --- | --- | --- |
| CS stream lookup | Exact advertised fixture/same-ID meta; valid16-stream JSON arrived in16.039s, beyond Fotty's12s deadline | CS-only request23s/transport24s implemented. Metadata and sibling budgets unchanged. Delayed-response regression and142CS tests pass. Full physical hold remains incomplete. |
| StreamViX football parsing |73 unrelated categories exceeded64 cap; explicit Simulcast programme invalidated real pairs | Keyed football parsing and exact programme exclusion fixed;38tests pass. Current stream response empty, not playback-qualified. |
| PL fixture continuity |20:00UTC terminal-rollback admission failure made the cohort unavailable and AS stopped listing this accepted fixture; normal cron later recovered | Focused isolation repair merged asPR113/e5a273f and deployed as2026-10-31.fixture-isolation-1 after the repeated21:23/21:28 failure.496full backend tests and102focused tests pass. Disputed/stale LIVE facts stay held; unrelated valid rows remain admitted. |
| AS delivery | Actual guarded relay returned403; zero decoded frames | Unqualified for this observed delivery. No speculative headers/authentication workaround or global disablement. |
| Flix delivery | All six early deliveries returned502/504; later normal app showed the correct Villa–Fulham programme on FS1/FS2 | Volatile, not permanently failed. FS2 had a manual visually advancing hold over90s with the same selected label; no instrumented attempt/frame-counter pass. Later failures also observed. |
| Score808 | Exact listing and descriptor admitted. Hosted XCTest WebKit entry aborted; ordinary app separately failed to start after retry | Automated web entry removed from the tool's normal path; explicit manual gate. Harness failure and real normal-player failure remain separate. |
| StreamEx | Catalog/resolution failure during checks | No current delivery proved. |
| CNC / TV | Enabled modules support reviewed NHL / Willow scope respectively | Unsupported for this PL test; not two extra football providers. |

## Consolidated second batch —31October21:11–21:17UTC

| Module | Actual result for Aston Villa–Fulham |
| --- | --- |
| CS | Six admitted alternatives. CS2 passed the instrumented90second hold:878decoded frames,93.54seconds media progress,23.665second startup. CS1 failed fresh resolution; CS5 changed its fresh delivery choice and was not tested. CS3/CS6 were denied at manifest destination admission; CS4 failed native startup. These results are not a family-wide outage. |
| Flix | All six admitted direct deliveries returned upstream manifest502 (FS4:504), with zero decoded frames in this run. Earlier transient manual playback stays separate. |
| Score808 | Matching web option present. Explicit manual web gate; no automatic decoding pass. Earlier ordinary-player failure remains recorded. |
| AS | No exact listing. Independent bounded refresh of its reviewed football catalogue at21:13UTC returned19rows and none containing either team. This is a current catalogue omission, not proof all AS streams are down. |
| StreamViX | Correct matching listing; current stream entries empty. |
| StreamEx | Catalogue/resolution failed. |
| CNC / TV | Unsupported for this Premier League fixture. |

The batch returned exit0 because the matrix was collected, not because all
providers played. The report keeps per-delivery failures and an explicit
execution state; crashes/interruption cannot turn into collection passes.
CS2's old timeout diagnostic also records that the same resource later completed;
that retained historical failure is not a current failed hold.

## Verification and limits

One consolidated Debug build205 succeeded and ran on Jet iPad. Previously
completed180focusedCS/SV tests remain valid;4Python runner tests,44local fixture
policy/registry tests, syntax and native membership checks pass. The new Swift
report-redaction regression compiled but was not separately executed. Product
sources were unchanged during this batch. Owned build/results/raw logs and the
keep-awake process were removed;16GiB free remained. See batch-2-scope.json,
batch-2-cleanup.json, batch-2-metadata.json and batch-2-physical.json.

The90second CS2 decoding result is instrumented. A separate normal-app run
confirmed CS2 selected with the correct Villa–Fulham programme on Sky Sports;
manual programme observations are recorded separately and do not invent
same-player/item identity between the two runs.

The tool calls the actual enabled-source inventory, accepted fixture parser,
source adapters/resolver, guarded relay, AVPlayer and decoded pixel buffers.
Its direct lookup probes are independent of shared-registry gating; registry
association counts do not prove the registered playback path. Fresh ESPN exact
teams/date/kickoff/in-progress status corroborates the accepted schedule. The
app's status and security/admission rules are not rewritten by the tool.

## Remaining focused gates

- CS2 normal-picker programme check is complete:Sky Sports Villa1–0Fulham,
  clock55:51→57:25 (94seconds), CS2 selected observed at56:20. This is separate
  from the instrumented hold; no cross-run player/item identity claim. Playback
  was stopped and the normal app returned to Home. Receipt:cs2-normal-picker-programme.json.
- CS manifest destination denials need source-local contract evidence before
  any compatibility repair; security guards were not weakened.
- AS omission, empty SV stream list and upstream Flix delivery errors remain
  concrete source limitations. No arbitrary channels or expired descriptors
  were substituted.
- The subsequent missing-Watch incident separately authorized the focused
  official-catalogue isolation deployment; its accepted-state and activation
  preservation receipts are retained below.
- Shared-registry/Watch reconnection remains pending the isolated proof and
  focused remaining-source review; this task made no new Watch integration.

Phone, FPL and multi-stream code/settings were left alone. The source-collection
batch did not publish/deploy. The later focused backend repair was separately
authorized and deployed; no TestFlight. Earlier failed receipts remain separate.

## Missing Watch incident — deployed repair,31October

At21:23 and21:28UTC the old backend rejected the six-league publisher group
after one terminal-status rollback. The accepted Villa–Fulham row was live,
but its unavailable cohort revoked native lookup eligibility and hid Watch.

Owner explicitly approved protected publication/deployment and separately the
existing watchdog compatibility rebuild. PR113/e5a273f changes the fixture
policy/registry, release identity and regressions; no app rebuild, source
activation, FPL, multi-stream or TestFlight change. All496backend units and
186watchdog checks pass; full GitHub unit/type/lint/bundle/build/security gates
passed. An old status-boundary test now uses six distinct fixture identities,
preserving the new duplicate-record rejection. The unrelated score patch was
excluded.

Playback3a0c5136 andwatchdog6660fa8b use2026-10-31.fixture-isolation-1. Fresh
cloud reads verified normal PL coverage and live Villa–Fulham. Original watchdog
activation11October11:14:52UTC and all130notification identities were retained;
all existing playback activation/configuration flags were unchanged. The local
owner-alert reader's version import was aligned without resetting its state.
At approximately21:42UTC, Jet Home visibly showed Villa–Fulham Watch and the
other football Watch actions again. The existing player was only minimized and
restored; its connecting state is not a new decoded-playback pass.

Receipts:missing-watch-incident.json, fixture-isolation-deployment.json,
fixture-isolation-cloud-before.json, fixture-isolation-cloud-after.json and
fixture-isolation-bindings.json. No temporary deployment output remains.
