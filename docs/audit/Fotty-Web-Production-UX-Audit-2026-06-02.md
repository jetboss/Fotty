# Fotty Web Production UX Audit - 2026-06-02

## Scope

Audited public Fotty Web routes as a production match-day sports product:

- Home
- Live Board / Swarm
- TV Guide
- Tables
- World Cup Hub
- Watch pages
- Welcome
- Settings
- Subscribe / Plans
- Teams
- Saved
- Help
- Privacy
- Terms

## Changes Made

- Added a centralized fixture-name quality gate in `fixture-normalization.ts`.
- Blocked rough provider abbreviations from reaching public fixture titles or team chips.
- Suppressed duplicate featured fixtures on the Live Board when the same match also matches tracked-team personalization.
- Hid TV Guide quick-pick panels and guide grids when there are no rows to show, leaving one intentional fallback state.
- Reorganized Settings into Account, Match Day, Device, and Support sections.
- Replaced older one-off Saved and Teams empty copy with shared fallback states and clear next actions.
- Rewrote plan copy to focus on match-day convenience, reminders, source organization, support, account features, and local WhatsApp activation.
- Removed public legal copy that made Fotty sound like a prototype or active-development build.

## Fixture Name Gate

Public UI should not show provider-only abbreviations such as:

- `PP v San Diego Padres`
- `Boston Red Sox v BO`
- `WN v Miami Marlins`
- `AD v LAD`
- `Home v Away`

The normalization layer now treats short all-caps provider tokens as untrusted unless they are in a small public short-name allowlist. If a fixture cannot produce two trustworthy public team names, the title falls back to:

`Fixture details updating`

This is intentionally conservative: an updating fixture is more trustworthy than a wrong public match name.

## Route QA Notes

### Home

- Loaded: should show the match hub, Watch Queue, competition lens, news, table preview, and clear Live Board / Guide actions.
- Empty: shared fallback states should explain that match-day data is refreshing and point users to Live Board or World Cup Hub.
- Signed-out: should still explain value without implying the product is incomplete.
- Error: provider failures must not expose raw backend text.

### Live Board / Swarm

- Loaded: one featured fixture, then For You, Live Now, Starting Soon, Big Fixtures, and Up Next without duplicates.
- Empty: clear search/filter fallback with Clear Search and TV Guide actions.
- P2P mode: source rows must communicate guide confidence and watch readiness without raw provider URLs.
- Data updating: loading state should be bounded and visually intentional.

### TV Guide

- Loaded: mapped rows first, backup channels available behind a clear control.
- Empty: no dead grid; use one fallback state with Show All Channels and Live Board actions.
- Loading: skeleton first, then data-refresh fallback if loading times out.
- Updating: do not duplicate empty quick-pick panels.

### Tables

- Loaded: real standings/top scorers where available.
- Empty/error: polished fallback should say tables are being refreshed and keep users near fixtures.

### World Cup Hub

- Loaded: should feel like a flagship hub with countdown, opening match, group cards, upcoming fixtures, reminders, stories, and local timezone language.
- Preparing: fallback should say tournament coverage is being organized, not "coming soon" without context.
- Times: use the shared kickoff formatter so Home, Live Board, and World Cup Hub agree.

### Watch Pages

- Loaded: one primary watch surface, with calm status and source switching below.
- Signed-out: explain account value and point to Sign In.
- No verified watch path: tell users Fotty will keep checking and offer reminder/Live Board actions.
- Error: do not show raw provider failures as the main message.

### Welcome

- Loaded: should orient new users toward Live Board and World Cup Hub.
- Signed-out: should be useful without making the app feel gated first.

### Settings

- Loaded: Account, Match Day, Device, Support.
- Signed-out: primary action is Sign In; paid users should see their access state.
- Device: install, refresh, privacy, terms, and help are grouped together.

### Subscribe / Plans

- Loaded: local TTD/WhatsApp activation is clear.
- Copy: focuses on organization, reminders, source management, support, and account features.
- Avoid: "pay for streams" framing.

### Teams

- Loaded: tracked teams list and notification state.
- Empty: shared fallback with Open Live Board action.
- Error/loading: autocomplete can still use static catalog if live match fetch fails.

### Saved

- Loaded: reminders, bookmarks, recent sessions.
- Empty: shared fallback cards with Live Board and World Cup actions.
- Primary action: Open Live Board.

### Help

- Loaded: should answer install, reminder, and playback questions without internal technical language.
- Empty/error: not expected; route smoke should still confirm body content.

### Privacy / Terms

- Loaded: production-ready wording, no MVP/prototype/development framing unless legally necessary.
- Terms: subscriptions describe account activation and third-party availability without implying guaranteed streams.

## Verification

- `npm run build` passed in `web`.
- Local production route smoke on port `3020`: `/`, `/swarm`, `/guide`, `/tables`, `/world-cup`, `/watch/test-source`, `/welcome`, `/settings`, `/subscribe`, `/teams`, `/favorites`, `/help`, `/privacy`, `/terms` all returned HTTP 200.
- Browser audit on core routes found no visible `Fotty 2.0 concept`, `prototype`, `MVP`, `Home v Away`, `Loading...`, or equivalent leaked copy.
- `/api/matches` check found zero visible matches for the known bad fixture-name patterns; 14 rough rows fell back to `Fixture details updating`.

## Remaining Launch Notes

- Keep monitoring EPG refresh reliability so the TV Guide does not lose mapped coverage during high-traffic match days.
- Run a real mobile viewport pass before public World Cup launch, especially Home, Live Board, Guide, Watch, and Subscribe.
- Continue improving provider stream health separately; this audit intentionally focused on public trust, route clarity, and fallback behavior.
