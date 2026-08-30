# Reference-data freshness remediation — 29 August 2026

Status: all six approved engineering items are implemented in Unreleased source
on top of private build 44. No app version changed and nothing was installed,
uploaded, submitted or deployed.

## 1. One season-labelled competition catalog

`shared/reference-data/football-competitions-2026-27.json` is now the reviewed
source for the Premier League, La Liga, Serie A, Bundesliga, Ligue 1, Champions
League and Europa League. It records the season, verification date, expiry,
expected club counts and official source for each competition.

`tools/generate-football-competition-catalog.mjs` produces the iOS and web
catalogs. It fails for an incorrect count, duplicate club, cross-club alias
collision, stale generated file, malformed expiry or any release check after
30 June 2027. The source is static by design: it must be reviewed and replaced
for 2027/28.

Home/web domestic classification requires both teams to be current members and
rejects cup, friendly, youth, reserve and lower-division markers. Provider
labels cannot overrule a membership conflict. Explicit Champions League
identity retains precedence. Team-news topics, TheSportsDB badge bootstrap,
on-device social suggestions and web Team Alerts now consume the generated
catalog instead of separate rosters.

## 2. FPL snapshot and season safety

Raw cache files are replaced by version-3 envelopes containing endpoint,
saved-at time, season, optional official team fingerprint and payload. Reuse is
allowed only for the same endpoint and current season, never from the future,
and within these maximum ages:

- live gameweek: 5 minutes
- fixtures: 6 hours
- bootstrap: 24 hours
- manager, picks, history and leagues: 24 hours
- player summary: 72 hours

Once bootstrap membership is known, a conflicting or missing fingerprint is
rejected. Storage is pruned to 96 files and 90 days; the retired raw v2 cache is
removed. Local scenarios, journals, profiles, reviews, drafts and Coach history
derive their keys from `FPLSeasonIdentifier`, which rolls at the UTC July
boundary.

## 3. Release entitlement boundary

The reusable client key and `FOTTY_FULL_ACCESS` Release condition are removed
from source and both project configurations. Debug builds retain developer
access. Internal TestFlight builds retain the full beta through Apple's sandbox
receipt. A public receipt is locked to the safe surface; neither an old stored
value, an environment override nor the retired remote integrity poll can unlock
it. This is an internal-beta
boundary, not a paid-entitlement implementation; a public paid product still
needs StoreKit entitlement verification.

## 4. Strict fixture windows

`FootballRepository` no longer fills an empty requested date range with the 15
most recent fixtures from another window. The generic
`FootballFixtureWindowPolicy` keeps the caller's closed range exact, including
the honest empty result.

## 5. Duplicate roster migration

The stale iOS La Liga/Serie A/Bundesliga/Ligue 1 news and onboarding lists,
partial UEFA fallback lists, local social suggestions, web league sets and web
Team Alerts catalog were removed. Generated output preserves aliases and
official display names without making provider badge availability a condition
for showing a current club.

## 6. Privacy and disclosure reconciliation

The web Privacy Policy and Terms, iOS Privacy screen and Apple privacy manifest
now agree on active behavior: device-local profile/follows/saved items/messages
and FPL planning state; public FPL manager-ID lookup without a password;
opt-in question/context processing through the Fotty Cloudflare Worker and
DeepSeek; local notifications; third-party player pages; and redacted local
diagnostics that are not uploaded automatically. Retired PocketBase email and
credential declarations were removed. This is an engineering reconciliation,
not legal advice or App Review approval.

## Verification

- shared catalog generation/check: pass
- project and `PrivacyInfo.xcprivacy` plist validation: pass
- web units: 86 passed, zero failures
- web lint: zero errors; 91 pre-existing warnings remain
- optimized Next.js production build and TypeScript: pass
- generic iOS normal Release: pass
- generic iOS Review Safe Release: pass
- seven focused new Catalyst policies: pass
- full Catalyst unit suite: 219 passed, one existing opt-in HLS soak skipped

The new regressions cover catalog membership/expiry, strict fixture ranges,
distribution receipt policy, FPL July rollover and snapshot age/season/catalog
rejection. The web equivalents execute in the passing unit suite. An initial
Catalyst host stalled while another Xcode device test was active; it was stopped
after a bounded wait. Both the focused and full uncontended reruns completed
successfully, so the initial infrastructure stall is not treated as a product
failure or as evidence of a passing run.

No simulator, device install, UI-test helper, provider probe, paid Coach call,
Worker deployment, TestFlight action or public submission was used. One
cleanup-protected DerivedData directory was used per sequential gate. Every
owned root and launched Catalyst host was removed. Disk remained at
approximately 54 GiB free.

## Remaining operational gates

Before 1 July 2027, verify all seven official memberships and generate the next
season manifest. Before any
public paid release, replace the beta receipt distinction with a real StoreKit
entitlement and obtain legal review of the published policy/terms.
