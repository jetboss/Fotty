# Reviewed sports TV guide

Source candidate2026-10-31.tv-guide-1 extends the existing reviewed ESPN Uruguay weekly RSS metadata. It adds no feed, request quota, cron, account or media probe. The cloud collector maintains it automatically within existing budgets; no owner Mac or AI job is required.

The optional `shared-broadcast-tv-guide-v1` durable sidecar holds up to300 source-owned entries with original observation/expiry and a4-hour guide lifetime. Reads never renew it. Invalid, ambiguous, expired or failed guide storage cannot revoke the established accepted broadcast registry. Weekly starts have no explicit ends and therefore never establish Now/live status.

The existing V1 Willow and V2 football projections are unchanged. Clients must send the existing V2 negotiation and exact `X-Fotty-TV-Guide: reviewedtv-guide-v1` capability for the new guide and derived MLB/NHL assignments. All3 headers participate in Vary/CORS. Derived assignments remain read-time projections, never new accepted-state record types, preserving rollback of the original registry schema.

Football/Willow retain their current match policies. Added MLB/NHL joins require an active reviewed official fixture scope, exact full teams and official men/senior squad, one fixture for that pair/date, fresh source/official receipts, original expiry, exact regional station and explicit coverage starting0–60minutes before unchanged kickoff. Conditional/ordinal/replay entries remain guide-only. Other sport programmes can appear in the guide without activating unreviewed fixture sources.

Validation:534 protected-checkout unit/runtime cases;170 watchdog policy and16 watchdog runtime cases; playback/watchdog dry bundles. A shared synthetic backend-generated snapshot is decoded by native tests to catch wire-contract drift. These are not live programme or playback qualifications. PL/UCL normal-Watch acceptance remains pending for an eligible live event.

Owner approved publication, deployment and the existing watchdog compatibility rebuild together. Deployment must preserve original activation, accepted snapshots, incidents, source selections, limits and bindings. No native app, FPL/multi change or TestFlight release is part of this backend PR.
