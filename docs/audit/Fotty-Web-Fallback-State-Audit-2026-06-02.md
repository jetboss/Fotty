# Fotty Web Fallback State Audit - 2026-06-02

## Summary

Fotty Web now uses shared product-quality fallback states for loading, empty, updating, signed-out, unavailable watch paths, World Cup preparation, and data refresh cases. Public pages should explain what is happening, avoid raw provider language, and give a clear next action instead of showing blank sections or indefinite loading text.

## Route States

| Route | Loaded | Loading | Empty | Error / Updating | Signed Out | Stream / Watch |
| --- | --- | --- | --- | --- | --- | --- |
| Home `/` | Match hub hero, featured fixture, watch queue, competition lens, headlines, stats | Home skeleton, then match-board updating fallback if refresh exceeds timeout | Empty fixture sections point users to Live Board and TV Guide | Match board updating or stale-feed banner with retry | Sign-in prompt explains sync/reminders/native app value | Watch buttons use normalized fixtures and verified watch links |
| Live Board `/swarm` | Match mode and P2P mode show filtered cards and control room | Shared loading state plus skeleton rows | Shared empty states for no matches/channels and over-narrow P2P filters | Feed status banner with retry; no blank board | Public discovery remains browsable | P2P/channel rows point to Watch and Guide |
| Watch `/watch/[id]` | Video stage, match hub, diagnostics, telemetry, backups | Shared loading state for direct event lookup; P2P warmup remains bounded | No verified stream state when playback path cannot be verified | Raw broker/provider failures are logged internally and shown as calm watch-path copy | Access gate explains sign-in/live access value and links to guide/plans | No verified watch path offers retry, TV Guide, and Live Board fallback |
| TV Guide `/guide` | Channel-first grid, rails, mapped/backups split, region/sport filters | Skeleton rows, compact updating pill, timeout to guide-updating fallback | Shared empty state with Show All, Live Board, retry path | Guide updating state directs to Live Board while EPG refreshes | Public guide remains visible | Channel rows link to Watch |
| Tables `/tables` | League standings and top scorers | Existing skeleton rows | Top scorers no longer disappear; standings/scorers show refresh states | Tables refresh copy directs back to fixtures | Public route | Not applicable |
| World Cup `/world-cup` | Hub hero, countdown, search, tabs, stories, groups, watch readiness | Pull refresh and route data refresh | Shared World Cup preparation state when tournament fixtures are absent | Stale feed badge when refresh fails | Public route | Watch readiness explains fixture/watch-path status |
| Help `/help` | Install, reminders, playback troubleshooting, privacy, support | Not data-dependent | No blank sections | Clear troubleshooting next actions | Public route | Guides users to Live Board/backups |
| Welcome `/welcome` | Welcome hero, live-board value, web/iOS positioning | Server feed fallback defaults to zero live count | Feature copy stays intentional if feed has no live matches | Public route remains useful without feed data | Public route | Links to Live Board/Home |
| Login / Protected | Account form and signed-in access summary | Button-level pending states | Not applicable | Sanitized auth error copy; raw backend errors logged internally | Sign-in value copy explains account/watch benefits | Protected watch page uses access gate |

## Public Copy Rules Enforced

- No route should rely on only `Loading...`.
- No empty section should collapse to blank space.
- Raw provider and broker failures are not presented in primary user-facing watch fallbacks.
- Placeholder fixtures such as `Home v Away` are handled by the fixture normalization layer and should appear as updating data only where unavoidable.
- World Cup empty states communicate preparation and tournament rollout, not failure.

## QA Checklist

- Confirm `/`, `/swarm`, `/guide`, `/tables`, `/world-cup`, `/help`, `/welcome`, `/login`, `/settings`, and `/watch/test-source` return HTTP 200 locally and on production.
- Confirm TV Guide timeout shows `TV guide is updating` with Live Board and retry actions.
- Confirm tables show standings/scorer refresh cards instead of disappearing panels when football-data is unavailable.
- Confirm signed-out watch page explains sign-in/access value and links to TV Guide/Live Board.
- Confirm failed direct or P2P watch paths show `No verified watch path yet` without raw error codes.
- Confirm mobile pull-to-refresh leaves a simple loading/updated affordance and does not cover primary content.
- Confirm World Cup Hub shows preparation state when no tournament fixtures are in the live feed.
