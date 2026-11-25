# Fotty Badge and Sport Motion Audit — 2026-08-31

## Outcome

Fotty now uses one team-identity contract and one sport-motion contract. Badge
failure is non-destructive: a failed or absent image keeps a deliberate team
monogram instead of an empty hole. Loading and selection motion follows the
active sport rather than displaying a football everywhere.

## Live artwork result

`node tools/audit-team-badges.mjs` resolved and signature-checked 272 artwork
URLs without retaining image files:

| Catalog | Valid | Total |
| --- | ---: | ---: |
| Source-controlled 2026/27 football names | 148 | 148 |
| NBA | 30 | 30 |
| WNBA | 15 | 15 |
| MLB | 30 | 30 |
| NHL | 32 | 32 |
| CPL | 7 | 7 |
| IPL | 10 | 10 |

Thirteen URLs are intentionally shared by source-controlled names/aliases for
the same club. No suspicious cross-club artwork collision remained. The audit
initially exposed one real collision risk between Paris FC and the `Paris`
alias for Paris Saint-Germain; matching now preserves identity-bearing terms
such as `FC`, so the two clubs resolve independently.

## Badge delivery changes

- Football badges bootstrap through one league-level metadata request for each
  supported competition instead of concurrent per-club SportsDB searches.
- The slow/free SportsDB catalog remains a fallback for CPL, IPL, Argentinian
  basketball, and a one-off unknown-team search.
- Current WNBA and NHL fallbacks are bundled alongside NBA and MLB fallbacks.
- Current CPL names and provider spellings have bundled artwork fallbacks.
- Exact provider aliases for LASK, Viking, Celje, Hapoel Be'er Sheva, and
  Salzburg are stored in the generated 2026/27 competition catalog.
- `TeamBadgeWindow` remains the UI boundary. Remote artwork, cached artwork,
  and the monogram fallback occupy the same measured window, so rows do not
  jump while images arrive.

The original per-team bootstrap was stopped during this audit after the free
provider returned a two-minute rate limit at 25 requests. The replacement uses
bounded league-level requests and prevents that cold-start request stampede.

## Motion language

`SportLoadingView` provides distinct movement and symbols for:

- football, cricket, tennis;
- basketball, baseball, hockey and American football;
- motorsport and combat sports;
- a multi-sport state and a truthful generic fallback.

The active Home sport emblem receives a small, one-shot sport-specific spring.
Badge artwork fades into its fixed window. Loading motion is used in Home,
Match Center, stream resolution, Arena discovery and player preparation.

The old football-only loader and the user-facing P2P waiting screen were
removed from shared playback paths. Player preparation no longer presents
peers, chunks, a secure handshake, or an “abort connection” action.

## Motion guardrails

Continuous animation is allowed only while the app is active, Low Power Mode
is off, and Reduce Motion is off. Sport loaders run at no more than 30 fps;
shimmer runs at no more than 24 fps; the compact momentum pulse runs at no more
than 20 fps. Reduced motion keeps the sport symbol and information without
movement. Decorative animation is not layered over playing video or native
player controls.

`SportCelebrationView` is available as a one-shot primitive but is intentionally
not connected to inferred events. It must only be shown after a verified goal,
wicket, or equivalent scoring event; visual polish must not invent live facts.

## Verification

- Live artwork audit: 272/272 valid; no suspicious shared URLs.
- Generated football catalog drift check: passed.
- Final Catalyst unit suite: passed after all provider-bootstrap and motion changes.
- Final generic iOS Release build: passed without signing or a simulator.
- `git diff --check`, generated-catalog drift and provider identity vectors: passed.

Device visual acceptance should happen through the next shared TestFlight build
so the same artifact is evaluated by every tester.
