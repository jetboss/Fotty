# Fotty private-product recovery record — 30 August 2026

## Outcome

Fotty remains a private, invite-only product. Recovery is user-controlled and
does not require a Fotty account or a new cloud service. The implementation is
complete in local source and passes the simulator-free automated gate; it has
not been versioned, installed or uploaded.

## Recovery contract

Settings → Privacy & Local Data → Private Backup creates a versioned
`.fottybackup` file. A user-chosen password of at least 12 characters derives a
256-bit key with PBKDF2-HMAC-SHA256 (120,000 iterations and a random 16-byte
salt). AES-256-GCM authenticates and encrypts the payload. The password is never
persisted and cannot be recovered by Fotty.

The previewable payload includes appearance and sports preferences, followed
teams/leagues, saved Matchday identity/timing, the public FPL manager identifier,
and manager-scoped local squad drafts, scenarios, journal entries, reviews and
Coach strategy profile.

It excludes passwords and credentials, provider URLs/source identifiers,
cached feeds, Coach conversations or prompts, AI consent, notifications and
reminders, diagnostics, profile photos and local messages. Saved matches must
resolve against the current catalog after restore rather than replay a stored
provider route.

Restore checks the envelope version, encryption parameters, plaintext size,
schema, collection limits, duplicate identities, bounded strings and FPL
manager consistency before changing state. SwiftData changes save before
UserDefaults replacement; a failed save rolls back. A successful restore clears
AI consent and notification reminders, invalidates cached FPL matchday context,
and tells the retained FPL workspace to reset and load the restored manager.

## Evidence

- AES/PBKDF2 round-trip, ciphertext non-disclosure and wrong-password rejection.
- Capture exclusions for provider routes, Coach history, diagnostics and consent.
- Valid state replacement with sanitized follows/saves and revoked consent.
- Invalid duplicate payload rejection without mutation.
- Shared football identity generation and five provider vectors pass.
- Complete Swift unit suite and unsigned generic iOS Release pass through
  `tools/ios-ci.sh`, with no simulator.

## Open physical acceptance

Exercise real Files export/import, wrong-password and cancellation paths,
preview counts, restored state, reminder revocation and renewed Coach consent on
hardware. This work did not allocate a build, change a device, upload to Apple,
deploy the Worker/web product, call a paid model or modify testers.
