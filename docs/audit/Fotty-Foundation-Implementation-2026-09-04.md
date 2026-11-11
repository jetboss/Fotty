# Fotty — first private-product foundation batch

Date: 4 September 2026. Status: **implemented and locally gated; not distributed
or deployed**. This is batch 1 of `../FOTTY-PRODUCT-EXECUTION-PLAN.md`, not
completion of the full product strategy. It accompanies the earlier five local
repairs recorded in `Fotty-Reliability-Fixes-2026-09-04.md`.

## 1. Native playback relay boundary

`LocalStreamProxy` and `LocalStreamProxyPolicy` now bind to loopback, require a
per-session capability and accept only registered destination routes rooted in
the selected native media. The arbitrary destination query is removed. Manifest
descendants are registered within a bounded route table; partial registration
failure does not leave partially admitted routes. Stopping revokes the session
and cancels listener, connections and upstream tasks.

Upstream requests use ephemeral storage with no shared cookies, credentials or
cache. Header scope is explicit; sensitive/custom headers remain on the initial
origin, while typed cookies retain domain/path/secure/expiry constraints. WebKit
handoff passes only cookies related to the selected media host, not its complete
shared cookie store. Redirect requests rebuild credentials and revalidate
destinations. HTTPS/public-address checks include DNS preflight.

Default bounds: 12 connections, 16 KiB request headers with a five-second header
deadline, 1 MiB input/2 MiB rewritten manifests, 4,096 retained routes, 128 MiB per
resource, 30-second request inactivity, 150-second resource lifetime, five
redirects and a three-second DNS preflight. Current-manifest routes are protected
from LRU eviction during registration. Normal and MultiView owners fence proxy
startup against cancelled/replaced requests.

Limits: DNS preflight is **not address pinning**; URLSession resolves again,
leaving a DNS-rebinding race. This is hardening, not a complete penetration-test
claim. HTTP/nonpublic routes, unsupported manifest variables, oversized resources
and cross-origin custom authentication fail closed. Real providers that depend on
these behaviors may need the existing WebKit path. Exact-device startup, controls,
PiP and continuity remain acceptance gates; unit tests do not prove compatibility.

## 2. Private, bounded paid Coach

DeepSeek remains the strategic reasoning provider. Scoring/rule answers remain
deterministic; on-device tools do not spend paid allowance.

- Individual high-entropy invitation codes are represented by SHA-256 digests
  in a Worker secret allowlist. Missing/revoked codes cannot start paid work.
  TestFlight membership and the installation ID are not authentication.
- The app has a secondary Settings → Privacy & Security → Coach Access page.
  Codes use non-synchronizing, device-only Keychain storage, not preferences,
  diagnostics or Fotty backups. Requests send a code only to the configured
  HTTPS endpoint and reject redirects. First use after a missing local install
  marker clears any surviving older Keychain entry. Storage access is serialized.
- Missing access, allowance or minute-limiter configuration fails closed.
- The owner chose **50 paid attempts per UTC day shared across the whole group**.
  One globally named Durable Object serializes reservations and persists the
  count before admitting model work, including across object recreation.
- Paid attempts are not successful-answer credits or an exact bill ceiling.
  Failed/cancelled attempts can still count; uncertain charges are never refunded
  automatically. A new UTC day resets the counter on the next reservation.
- One 50-second deadline covers parsing, evidence, allowance and the model call.
  Client cancellation propagates upstream; official evidence and model response
  bodies are bounded. There is no automatic paid retry. Request completion aborts
  residual work, including siblings of failed evidence requests.

Checked-in values are `FPL_COACH_DAILY_LIMIT="50"` and
`FPL_COACH_PAID_ENABLED="0"`. They do **not** change the existing production
service. Local `sourceVersion` is `2026-09-04.coach-safety-1`; it is not a deployed
revision. No real code was generated, sent or provisioned and no paid request was
made. Bearer invitations are revocable/shareable credentials, not App Attest or
proof of device/FPL ownership. Rollout, safe pause and old-app compatibility are
documented in `../operations/PRIVATE-COACH-ACCESS.md`.

## 3. FPL plans that survive and remain valid

`FPLTransferStagingStore` persists unfinished work separately from the validated
saved draft, scoped to manager and season. Undo retains ten checkpoints. Live
multiplier changes are normalized away; changed published picks, gameweek or
budget retain edits and require an explicit Keep/Reset decision instead of
silently replacing the working squad.

Saving verifies manager, season and the entire current acknowledged baseline,
then uses the existing shared squad validator and current budget. Caller-supplied
budget inflation is rejected. Two-transfer suggestions validate the complete
resulting squad and available funds and can search past an illegal first pair.
Known selling prices are used; unknown private bank/selling facts remain stated
assumptions, not asserted official values. This does not submit official FPL moves.

Backup restoration intentionally replaces local plans after complete validation.
It clears only Fotty-scoped staging keys, preserves unrelated preferences and
resets any open transfer editor/picker, including a same-manager restore. Working
staging is excluded from exported backups; validated saved plans retain their
existing backup contract. Disconnect preserves scoped local drafts, as before.

## Verification completed on final combined source

| Gate | Result |
| --- | --- |
| Full simulator-free Catalyst unit gate | Passed through `tools/ios-ci.sh`, sequential with two build jobs |
| Generic unsigned iOS Release compilation | Passed in the same bounded gate |
| New native behavior coverage | 21 relay tests, 14 transfer safety tests, two credential validation/header tests; existing backup test extended |
| Full web/Worker suite | 83 passed, zero failures/cancellations/skips |
| Worker package dry-run | Passed; both Durable Objects, both rate limiters, disabled paid flag and limit 50 present |
| Whitespace/error-marker check | `git diff --check` passed |
| Independent review | Relay scope/transport tests, FPL restore ownership and paid authorization/cancellation reviewed |
| Resource cleanup | Both task-created temporary roots removed; approximately 31 GiB free before and after native work |

The Xcode script's quiet output reports gate success, not a full-suite test count;
no inferred aggregate count is presented here. Native units include mocked HTTPS
and actual loopback transport, not paid model calls or third-party video decode.
The deterministic provider identity vectors also pass in the native gate.

No simulator, physical UI-test runner, device install, archive, TestFlight upload,
production deployment, source publication or version bump occurred. Source is
still labelled 2.0.0 (58), but this work is after that distributed artifact.
Recorded installs remain Jet iPad 58, owner iPhone 53, other 16e 50 and shared
TestFlight 55; no new independent device query was needed for this local work.

## Before a release or paid-service activation

1. Allocate a unique build for the combined candidate and record exact source.
   Do not publish the dirty old-ancestry checkout as a shortcut.
2. On explicitly selected iPhone/iPad, qualify native and WebKit startup,
   pause/resume, source change, background/PiP, network interruption and a bounded
   long-session hold. Check fallback if a provider requires rejected credentials.
3. Exercise Transfer Lab tab/app return, refresh/deadline conflict, Undo, manager
   switch and a real encrypted backup restore. Confirm no silent loss of work.
4. Check Coach Access in Light/Dark/large text, locked-device storage errors,
   remove/re-add and reinstall behavior. These Keychain/UI interactions were not
   exercised by the pure credential tests.
5. Follow the separate protected-service rollout with owner approval. Inspect
   actual production bindings/settings/revision, deny revoked/missing access and
   verify deterministic answers. A real model probe needs separate approval and
   consumes one of the group's attempts. Do not roll back to an unprotected paid
   endpoint to resolve an access failure.

Next implementation priority is the connected sports journey: fair bounded
discovery, saved/reminded CPL Watch, canonical multisport follows and coherent
event state. The remaining whole-product findings and roadmap batches stay open.
