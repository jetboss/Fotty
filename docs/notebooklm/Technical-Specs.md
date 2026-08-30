# Fotty Technical Specifications

## Product graph

Fotty is an iOS/iPadOS live-sports companion with a Live Activity extension and FPL widget. The public web companion is a static Next.js export on getfotty.com. A Cloudflare Worker is the only active server-side runtime.

The retired Android prototype, homelab, PocketBase accounts, AceStream/P2P proxy, and Cloudflare Tunnels are not product dependencies and must not be restored as fallbacks.

## Data boundaries

- StreamEx and Score808 families provide the broad live catalog and provider pages.
- Official FPL endpoints provide Premier League fixtures, manager evidence, and the first live-score source.
- football-data supplies the schedule fallback.
- API-Football is a quota-bounded Premier League live-score fallback through the Worker.
- Profiles, messages, saved matches, reminders, and FPL planning are device-local.
- Provider credentials and the DeepSeek Coach key remain Worker secrets.

## Playback

Web providers stay inside the contained WebKit path. Native HLS/MP4 candidates may hand off to AVPlayer when verified. Native playback activates the playback audio session only at play/PiP boundaries and uses the background policy that permits continued PiP playback.

Provider readiness means decoded, advancing media—not a loaded page, catalog row, or viewer count. Startup and stall recovery are attempt-scoped and bounded.

## Deployment and verification

- No simulators on this workstation.
- Reuse one bounded DerivedData directory and remove it after verification.
- Small owner-only checks may install directly on a connected device.
- Tester-facing changes use a new TestFlight build.
- GitHub protects `main` with workflow syntax and secret-scanning checks.
- Web CI covers unit tests, TypeScript, lint, Worker validation, and build.
- iOS CI runs provider identity checks, Catalyst unit tests, and a generic unsigned iOS Release build.
- CodeQL covers Actions, JavaScript/TypeScript, and Python. Swift remains under the Xcode gate until Xcode 27 extraction is reliable.
