# Independent discovery and catalog freshness — 28 October 2026

## Scope and current gate

This source-only candidate implements the mechanisms researched with three agents
in `docs/audit/Fotty-Established-Apps-Discovery-REA-2026-10-28.md`. It adapts the
mechanisms independently; no upstream implementation was imported. No device,
source setting, build number, cloud service or TestFlight distribution changed.
Jet remains on181 and the phone on177. FPL and multi-stream feature files remain
unchanged. Source verification is not qualification of current provider media.

## Implemented behavior

| Area | Behavior and concrete failure addressed |
| --- | --- |
| Independent provider plans | Enabled reviewed providers are selected by supported sport and exact dated fixture identity. An absent shared-publisher catalog does not suppress optional sources. Score808-only configurations retain their shared and direct-site lanes. Match details with a complete identity do not wait for the shared catalog before independent discovery. |
| Exact event bindings | CS/AS successful joins carry ephemeral fixture → provider event → advertised stream IDs, competition/squad/cricket context and short freshness. Bindings are excluded from saved session JSON. A fresh candidate cannot migrate to another date, squad, format, ordinal or Test day. |
| Fresh CS/AS resources | Explicit single-stream checks bypass manifest/catalog snapshots. Cached capability mismatch or an exact empty descriptor gets one eligible fresh check; empty catalogs have shorter retention. Disabled providers, cancelled generations and stale callbacks cannot publish choices. |
| Foreground candidate evidence | Home may check one eligible visible/current fixture every90seconds while active and no stream or other lookup is running. Each call checks at most two enabled reviewed optional providers within8seconds. The24-record in-memory index has90second provider cooldowns and24/hour,96/day preflight-start caps. Manual discovery remains available. This does not create a cloud collector or poll every fixture. |
| Honest availability | Fresh compatible candidates may enable the existing timed Watch action. Negative/failed checks never fabricate a stream, set a fixture LIVE, or block a new manual check. Provider outcomes retain checking/candidate/empty/failure/stale distinctions internally. Generic Willow/Fox channels do not establish a named fixture's availability. |
| Descriptor negotiation | Explicit single-stream CS/AS native playback can obtain one fresh descriptor for the same selected event/stream within the existing retry budget. Fresh transport fields replace old credentials/grants; the selected UUID and opaque label remain. Delivery-token rotation is allowed only after fresh admission and a unique same-choice join; stable upstream keys must still agree. Known expired media cannot be replayed after failed renewal. Metadata expiry alone is not proof that media expired. |
| Typed recovery | Single-stream recovery uses causal current HTTP/error evidence.401/403 and incompatible/decode/unsupported contracts do not masquerade as timeouts;408/5xx retain bounded retry behavior. Old access-log or unrelated relay statuses do not become the current cause. Multi-stream callers keep their existing policy path. |

Existing18second append-only on-demand discovery, current-event terminal and
conflict authority, TLS/public-IP/redirect/header restrictions, native ownership,
explicit Pause and source/attempt cancellation remain. Foreground preflight is
limited to optional reviewed providers; shared-publisher/Score808 discovery stays
on demand. Defaults are not enabled by this candidate.

Positive cache reuse requires a current exact binding and lasts at most60seconds;
it cannot extend that binding or a known media expiry. Reviewed unbound adapters
may contribute current candidate counts but cannot cache-reuse their delivery.
There is no promise that an external publisher will always provide a match.
The24/hour and96/day caps count provider lookup starts, not individual HTTP
requests. Existing bounded CS lookup can perform up to six metadata requests
and AS up to four; the8second foreground owner can cancel either earlier.

Final integration review also repaired two concrete edge cases. Home retains
its next check time and fixture rotation across catalog task replacement, so
routine refresh cannot starve all but the first match. Explicit Pause during
suspended descriptor negotiation blocks late adoption/startup. Play either
continues that same pending lookup or explicitly requests a fresh one after its
paused response was discarded, without resetting automatic retry counters.

## Verification

The final core run contains580 tests:578pass, zero failures and two physical-only
skips. Repeated runs are not additional unique tests. The final foreground
eligibility fence was reviewed after that run and is included in the exact iOS
Release compile; automatic tests disable real foreground discovery. No physical
UI or media behavior is claimed for that final guard.

See `verification.json` and `source-inputs.sha256` for the final local result and
exact compiled inputs. The focused unit gate covers CS/AS adapters, fixture and
source identity, discovery coordination/index, recovery policy and football/
cricket catalog rules. The final selection explicitly includes the separate
index, preflight schedule and native-preparation XCTest classes, plus existing
optional-source admission checks. HTTP behavior uses controlled URLProtocol
responses; ViewModel renewal tests inject resolution and reject validation before
audio or media starts.

The first complete local run exposed an invalid new test label (CS7); the test
was corrected to admitted CS3 without widening the source contract. A later run
from Documents stalled in an existing source-reading test. The final gate used
an owned temporary source snapshot with hashes verified against the repository;
no Mac permission changed. One shared JSON fixture was initially omitted from
that snapshot, then included and its failing test rerun successfully. Reruns
overlap and are not additional unique test counts.

Combining the separate test classes also exposed a test-isolation issue: a fixed
September fixture shared the production index with real-time ViewModel checks.
Availability policies now accept an index dependency with the same production
default; that fixture uses its own index. The clock-regression guard remains.

The two physical-only skipped tests are explicitly excluded from playback proof:

- `PlavioSportsAddonTests.testReviewedPlavioDeliveryDecodesThroughGuardedRelayOnPhysicalDevice`
- `PlaybackPolicyTests.testReferenceHLSMaintainsOneAttemptDuringSoak`

## Remaining acceptance

The candidate still needs an approved private iPad gate through normal Home,
match and source selection, a fresh live Premier League/Champions League and
supported cricket window, correct-programme observation,90second decoded
progression, controls and a failing-primary/working-secondary case. Those checks
have not run for this candidate. No skipped test, descriptor, compile or earlier
build181 playback receipt substitutes for them.

Further watchdog hardening proposed in the separate resilience research remains
a separate gate. Existing observation-only monitoring stays as deployed.
