# Private Coach access and daily allowance

Status: local implementation, 2026-09-04. The checked-in Worker configuration has
`FPL_COACH_PAID_ENABLED = "0"` and the owner-approved
`FPL_COACH_DAILY_LIMIT = "50"`. These source values are not evidence of a deployed
pause or protection. This guide does not authorize provisioning, code delivery,
deployment, activation or a paid request.

The allowance is shared by the entire private group: 50 paid-attempt reservations
per UTC day, not 50 successful answers per tester and not a money cap. A reservation
is persisted before a model request can start. Failed or cancelled attempts are
not refunded, including an ambiguous cancellation before provider work begins.
Cancellation cannot establish whether the provider charged. The next reservation
after midnight UTC starts the new day's count. Deterministic scoring and on-device
FPL tools use no paid model allowance; cloud scoring still requires network access
and its request rate limiter.

## Invitation handling

- After owner approval, create a separate cryptographically random 32-byte code
  for each tester and encode it as 64 lowercase hexadecimal characters. Do not use
  a shared group code, an FPL manager ID or the installation ID as the credential.
- Compute SHA-256 over the UTF-8 text of that lowercase 64-character code, not
  over the original random bytes. Store the resulting lowercase hexadecimal
  digests as a JSON array in the Worker secret `FPL_COACH_ACCESS_SHA256`. Keep the
  tester-to-digest inventory privately so individual access can be revoked.
- Never put actual invitation codes, provider keys or the secret allowlist in
  repository files, task output, shell history, logs, screenshots or diagnostics.
  Deliver each code through an owner-approved secure channel; delivery itself
  requires authorization. The DeepSeek key remains a separate Worker secret.
- Testers need an app build containing Settings → Privacy & Security → Coach
  Access. They save the code there and separately choose whether to consent to
  Cloud Coach. Saving confirms secure local storage, not server acceptance.

The app uses a non-synchronizing Keychain entry with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; invitation codes are excluded
from Fotty private backups and diagnostics. Requests attach the code only as an
Authorization header to the configured HTTPS Coach service, and redirects are
rejected. Removing a code in Settings removes that device's copy. It does not
revoke other copies or guarantee cancellation of a request already admitted.
This is bearer-code access, not App Attest, device attestation or proof of an FPL
account's ownership.

## Rollout checklist

1. Qualify the exact native build and Worker artifact with the local test/build
   gates. Use synthetic credentials and stubbed providers for offline tests.
   Staging deployment and external smoke checks require owner approval.
2. Distribute the app with Coach Access and securely deliver individual codes
   before activating the protected service. Older builds cannot supply the code;
   paid questions will receive an access error or the app's available local
   fallback. Communicate that compatibility boundary before rollout.
3. With separate owner approval, provision the allowlist and deploy the protected
   Worker initially paused. Retain both Coach rate limiters,
   `enable_request_signal`, the `FPL_COACH_BUDGET` binding and its migration.
   Missing or invalid access/allowance configuration must remain closed to paid
   requests. Do not enable paid access merely because deployment succeeded.
4. Read back the exact production Worker version and health `sourceVersion`,
   deployed enabled/limit values, secret presence and Durable Object binding.
   Verify that the app points to this same HTTPS service. Source configuration
   and a dry-run are insufficient production evidence. Inspect secret metadata
   without displaying credential values.
5. After approval to activate, set paid access to `"1"` with the limit still
   `"50"`. Run approved denial and deterministic-scoring smoke checks. One real
   paid probe requires explicit owner approval and consumes an allowance slot.
   Verify the resulting response, token usage and persisted counter change;
   record only redacted evidence tied to the exact app/Worker versions. Do not
   manufacture 50 paid calls to prove exhaustion; test that with a stubbed model.

## Revocation and emergency pause

For an individual revocation, remove that tester's digest from the secret
allowlist through an approved service update. Confirm rejection of a new request
with that code without exposing it. Issue a replacement only when authorized;
changing or deleting the local Keychain entry alone is not server revocation.

For an emergency pause, deploy or apply the approved configuration with
`FPL_COACH_PAID_ENABLED = "0"` and verify the production pause response. Keep the
protected implementation in place. Do not roll back to an older revision that
admits publicly accessible paid requests. Previously admitted provider work may
still incur a charge.

Preserve the Durable Object namespace, globally named object
`private-coach-global-v1`, and storage key `daily-v1` across pause, restart,
rotation and deployment. Do not delete or rename them, reset the counter, or
increase the limit to get around exhaustion. The counter is intentionally shared
across tester codes and Worker instances. Any allowance change requires owner
approval; provider billing controls remain a separate boundary.

Implementation references: [Worker admission and quota](../../web/workers/playback/src/coach-safety.mjs),
[Worker configuration](../../web/workers/playback/wrangler.toml),
[device credential storage](../../Fotty/Features/FPL/Services/FPLCoachAccessStore.swift),
and [Coach Access settings](../../Fotty/Features/Settings/Views/SettingsCoachAccessView.swift).
