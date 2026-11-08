# Direct watchdog owner email — disabled preparation

Prepared29October2026 against protected `83b1a44`. **Not activated, sent or deployed by this source gate.** Existing GitHub/chat observation remains intact. Do not treat this document or a successful build/test as sender eligibility or delivery proof.

## Material setup gates

- The owner supplied a private destination separately. Its real address does not belong in source, test fixtures, this document or public status.
- Root's initial29October read-only account check found no verified Email Routing destination. A later operator receipt confirmed the private owner destination verified at **29October2026 23:06:34UTC**. The real address remains private. This closes the destination-verification gate only; compilation did not verify it.
- Root also found neither `getfotty.com` nor the current web host's parent domain in this Cloudflare account's zones. A later account sending-domain list returned Unauthorized; no eligible, onboarded sender has been demonstrated. **Do not assume the proposed sender can send.** Establish a supported domain-onboarding route and verification facts before enabling anything; do not change DNS, add/move a zone or onboard a sender under this source-only task.
- The prepared code accepts only `watchdog@getfotty.com`. Using a different sender/domain requires a focused reviewed configuration-policy change; there is no arbitrary sender input.
- Cloudflare's current documentation requires an onboarded sender domain and supports a binding restricted to one fixed destination. It documents sends to verified destinations as free; this preparation enables no paid sending or arbitrary recipient path.

Official sources, checked29October:
[Workers sending API](https://developers.cloudflare.com/email-service/api/send-emails/workers-api/),
[fixed-destination bindings](https://developers.cloudflare.com/email-service/configuration/send-bindings/),
[verified-destination pricing](https://developers.cloudflare.com/email-service/platform/pricing/).
Recheck account eligibility and the deployed runtime's support at activation; documentation is not an account-specific onboarding receipt.

## Private configuration example — placeholders, not a complete deploy config

Keep the source flag `FOTTY_OWNER_EMAIL_ENABLED="0"`. After the factual sender/recipient gates and explicit activation authority, prepare a private copy/overlay of the **existing protected watchdog configuration**, preserving its name, original activation, namespace/migrations, variables and collection controls. Add only:

```toml
[vars]
FOTTY_OWNER_EMAIL_ENABLED = "0" # remains0 until factual activation gates pass
FOTTY_OWNER_EMAIL_ACTIVATED_AT = "<NEW_CURRENT_UTC_CUTOVER>"
FOTTY_OWNER_EMAIL_RECIPIENT = "<VERIFIED_OWNER_DESTINATION>"
FOTTY_OWNER_EMAIL_SENDER = "watchdog@getfotty.com"
FOTTY_OWNER_EMAIL_SEND_TEST = "0"

[[send_email]]
name = "FOTTY_OWNER_EMAIL"
destination_address = "<SAME_VERIFIED_OWNER_DESTINATION>"
```

Do not apply this snippet over existing `[vars]` wholesale. Do not add an unrestricted binding, cc/bcc, arbitrary recipient/sender or API credential. The code passes the configured recipient explicitly; the platform's fixed-destination binding supplies a second restriction. No real address is committed. No public mutation/test/send endpoint exists.

After a future activation, every subsequent watchdog deployment must retain the
private email binding and explicit approved email settings, just as it retains
the original collector activation. The source flag intentionally stays0;
`keep-vars` alone must not be assumed to preserve a variable declared in source.
Capture redacted channel state before/after deployment. A missing binding,
missing/garbled enablement flag or invalid configuration after an established
cutover is an actionable mismatch, not quiet first-time staging. Only the exact
string0 is a deliberate pause; it retains its queue. A pristine missing flag
stays quiet and does not create email state. Configuration-loss diagnostics do
not send or write pending state.

The sending call uses Cloudflare's structured `send({to,from,subject,text,headers})` API. A bounded nonempty `messageId` acknowledges service submission only. It does not establish inbox arrival, email-reading, mobile push or human response. Raw provider errors and IDs are never persisted or exposed.

## Cutover and preserved state

1. Capture redacted existing collector status, original activation, notice IDs/count and namespace identity. The current retained121-notice backlog is historical; do not replay it.
2. Choose a **new current UTC cutover** for email, not the original11October collector activation. On the first configured cron, committed notices at/before that cutover become known baseline IDs without sending. Post-cutover notices queue normally. An initial cutover older than30minutes fails closed; choose a fresh factual cutover rather than resetting durable state.
3. Email uses a separate `watchdog-owner-email-v1` key in the same existing Durable Object. It never acknowledges, rewrites or deletes the collector's incident ledger/outbox, leases, budgets or notices. No namespace migration is needed. A changed recipient/cutover fingerprint cannot silently reset an established email queue.
4. The existing cron drains only the **committed** outbox, after successful collection and on non-collection ticks. A failed collection may still drain earlier committed pending notices; uncommitted events cannot be emailed. No new provider/media checks occur.
5. Disabling the email flag pauses sends and preserves pending work. Re-enabling the same configuration resumes it. Do not delete/reset its private state to silence a failure or change its target.

## Bounded submission and failure semantics

- At most16 finite operations notices per grouped message, grouped by provider/stage. Only type, source, stage, failure class, scope, generation and observation time enter its body. No fixture/stream identifiers, media URLs, tokens, viewer history, attachments or private device data are sent.
- At most12 attempts per UTC day, including failures and the optional test, with at least5minutes between starts. Failures retain pending work and back off up to1hour; pending capacity is64 and known IDs are bounded by the existing513-notice ceiling. Unsaved overflow candidates are not marked known, and the original outbox remains available for retry.
- A durable fenced lease is stored before calling the binding. Concurrent calls/restarts cannot ordinarily submit the same live lease. Queues and attempt budgets survive restart. Successful service acknowledgment removes only that batch's pending entries.
- Timeout, unknown transport failure, process loss or a failed acknowledgment write can mean the service accepted a message without a stored receipt. Such work remains **ambiguous**, not delivered. A retry uses the same stable `FE-…` batch ID; duplicate emails are possible. The provider does not promise idempotency for that header, and this code does not claim exactly-once delivery.
- Sender/recipient/platform rejection is retained as a finite reason without private error text. No automatic address change, account action, DNS modification, source repair or deployment follows.

Public status exposes only finite channel state/counts/times and sanitized failure reasons, never the target, sender, configuration fingerprint, raw service ID or email content. The existing owner reader reports enabled failures, capacity or pending age beyond35minutes through the fallback channel. Disabled/unconfigured staging is expected and stays quiet. GitHub/chat remain useful fallback paths if direct email itself fails.

## Optional test and activation verification

Only after setup and actual send authority, `FOTTY_OWNER_EMAIL_SEND_TEST="1"` requests one clearly labelled **DELIVERY TEST** per established cutover. It is a separate batch, never an invented provider incident/recovery or a historical-alert replay. Repeated cron/restart cannot request a second test. Its service acknowledgment is not an inbox/read receipt. Return the flag to0 after the deliberate test; disabling email pauses an ambiguous test if necessary.

Activation must verify the exact protected source, fixed destination binding, verified destination, onboarded allowed sender, original collector state, fresh cutover/baseline count and later real cron processing. Check inbox arrival separately with the owner if needed. Preserve all121 historical notices and do not use `--initialize`, private-state deletion, test hooks or a canary email as proof that normal delivery, scheduling or playback works.
