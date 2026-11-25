# Fotty2.5 native experience — stages3/4

## Expanded visual implementation24October

The owner subsequently approved completing the core iPhone/iPad reference UI,
not just the focused disclosure/Settings patch described below. The resulting
composition, typography, adaptive presentation and verification are recorded in
[the UI implementation receipt](Fotty-2.5-UI-Completion-2026-10-24.md).
The sections below retain the original interaction contracts and dated focused
scope. Build175 is still frozen on both devices; no physical acceptance is implied.

Contract established24October2026. Evidence: current source inspection, not a
new native render. Normal2.0.1(175) on the owner iPhone and Jet iPad is frozen for
feedback. No device interaction, installation, TestFlight, FPL or multi-stream
work is authorized by this document. The implementation gate below is separately
approved for focused source changes; physical acceptance remains open.

This follows stages1–2 of the [2.5 roadmap](Fotty-Stremio-CS-Usability-Review-2026-10-23.md),
not a new theme. Preserve Fotty's team badges, sport equipment artwork, existing
tokens, dark default/light option, native controls and video-first player.

## Inspected baseline evidence — before this focused patch

| Surface | Foundation to retain | Focused friction / limit |
| --- | --- | --- |
| Home | `SportsDashboardView.swift:401` owns personalized current/upcoming sections; `:995` keeps identified flattened lazy entries; `:94` distinguishes deliberate filter scrolling from background updates. | `HomeScheduleRow` in `SportsDiscoveryViews.swift:735` opens a full details sheet for a nonwatchable row. Basic date/broadcast context can be read in place instead. Do not divert Watch. |
| Matchday | `ArenaDiscoveryView.swift:590` separates live, listed, upcoming, dated, unconfirmed and recent sections. The optional viewing window already has its own explicit purpose. | `personalMatchRow` at`:649` supplies Details/Save callbacks to `LiveEventCard`, but `LiveEventCard.swift:79` hides Details when Watch exists and`:118` leaves Save/Remove in a long-press menu. A watchable saved match has no visible ordinary-touch Remove action. |
| Search | `SearchView.swift:362` retains query; `:403` uses native search, keyed loading/results and empty states; `:686` reuses badge-aware fixture rows. | Its Details callback currently dismisses Search before presenting the same full sheet. Simple context should not discard the query/keyboard journey. Cold-index performance is stage5, not a reason to rewrite search here. |
| Settings | `SettingsScreen.swift:76` uses adaptive columns. `SettingsComponents.swift:89,168` stacks long labels/accessories at accessibility text. Source settings already use native List/Toggle. | The root “Preferences” mixes appearance, interests, planning and notifications. “Broadcast Sources” opens “Playback sources”; the source section's “Available” means configurable registrations, not proven live playback. Keep that distinction truthful. |

Shared layout already responds to actual window width and accessibility size in
`Design/Theme.swift:5`. The existing two-line normal-size team-name cap is a
stress-case inspection target, not proof that today's175 native screens clip.
Do not replace measured reflow with smaller text or a global font change.

## Common interaction contract

- Watch remains the dominant action and calls the existing current-policy path
  directly. Reading Details, opening a menu or resizing never starts a lookup,
  replaces playback, enables a source or restarts media.
- A secondary Details action may reveal a compact inline block: exact local
  scheduled date/time and the existing truthful broadcast explanation. Do not
  repeat large badges/names already visible above it. Richer existing details
  remain available for source checking/help; no new source action is invented.
- Keep one existing reminder owner. Saving alone does not opt into reminders;
  removing a save retains its existing reminder-cancellation semantics. The
  inline block does not add duplicate Save, Watch or Remind controls.
- Native More menus expose the existing Details and Save/Remove commands, with
  visible saved state and44pt project-standard hit regions. Long-press and
  accessibility actions remain alternatives, not the only discoverable path.
- Expansion is explicit and local to its stable event identity. It must not
  rebuild the scroll container, clear filters, reset query or manufacture a new
  event identity. A recycled/different event must not inherit expanded context.
- Preserve confirmed live vs provider-listed, finished, unconfirmed start and
  channel/programme distinctions. A channel is not a named fixture or EPG.

## Screen contracts

### Home — choose what to watch

**Primary action:** Watch an eligible current match. **Reading order:** title and
Search → active sport/interests scope → featured current match/other current
matches → Up Next → Browse Sports → later fixtures. Keep Home's current scope
visible; only explicit scope changes return to results. Background refreshes do
not move the reader.

**Compact:** badges and full meaningful team identity lead; Watch stays beside
the names where it fits. Future rows retain a countdown/reminder and concise
competition context. Details expands below that same row, not into another
full-width card carousel. Preserve the approved three-column sport composition
at ordinary phone sizes.

**Wide / accessibility:** keep the existing useful two-column fixture layout at
eligible window widths, one column for narrow windows/accessibility text. Each
expanded block stays with its match; no independent vertical scroll region.
Wrap names/qualifiers before moving actions below them; never shrink badges or
text to force the reference geometry. Use semantic type and nonoverlapping hits.

**States:** ordinary current/upcoming, no selected-interest fixtures, no listings,
refreshing, actionable stale/failed coverage, unavailable badge, expanded and
collapsed Details. Routine healthy refresh text stays absent; consequential
warnings keep their existing policy. Do not alter status or interest selection.

**Acceptance:** direct Watch is still one explicit action; expand/collapse leaves
interests and scroll intact; late live rows do not jump the page; long women's/
youth names remain distinguishable with real/fallback badges and no wrong crest.

### My Matchday — plan personal viewing

**Primary action:** act on a saved/followed match: Watch now, or manage an upcoming
reminder. **Reading order:** title/Browse → Full Matchday or viewing-window mode →
any specifically opened saved match → relevant date/status groups. This is a
personal plan, not a second unrestricted Home catalog.

Expose the existing Save/Remove and Details commands through the same native
More affordance used on Home, including when Watch is present. Compact context
belongs to its row. Keep changed-start and no-longer-listed evidence attached to
the saved item; do not hide consequential change information for cleaner cards.

**Adaptation:** retain grouped separators and useful two-column rows on a wide
iPad. The viewing-window controls may remain a bounded useful side column; a
narrow/large-text window stacks them in the existing reading order. Do not add a
permanent match-details sidebar or revive kickoff-clash promotion.

**States/acceptance:** empty personal plan → Browse/Follow; loading is distinct
from empty; cancelled/finished/awaiting rows remain nonwatchable under current
policy. Remove is visible without long-press and its action affects exactly one
saved match. Tab return, expansion and window resize preserve the current plan.

### Search — find a specific team, competition, sport or channel

**Primary action:** find and open an eligible result. **Reading order:** native
search input → recent/interests suggestions or explicit search progress → result
count → ranked, badge-aware results. Do not add another filter bar by default.

Simple Details expands in the result rather than dismissing Search. Preserve
the query and keyed result identity; selecting Watch uses the existing dismissal
and playback handoff. Richer details remain secondary. Keep fixture and generic
channel results distinct. No fuzzy match is added to playback admission.

**Adaptation/states:** two columns only when actual width/text size supports it;
otherwise one list. Interactive keyboard dismissal remains available; no blanket
tap gesture captures row controls. Retain blank, searching, no current listing,
partial/failed coverage, result and save-error states. “Not in this lineup” is
not a promise that the match/source never exists.

**Acceptance:** typing/cancellation cannot reveal an old query's context; expand
and collapse do not dismiss Search; Done and result Watch still work; long names
and channels remain readable with the keyboard and accessibility text present.

### Settings — change one understandable preference

**Primary action:** find a named setting and change it without guessing its
scope. Group existing controls by task: Appearance; Home & Matchday (interests,
favorite teams, optional clashes); Playback & alerts (sources, notifications);
Your data; Help & About. This is rearrangement, not new destinations or settings.

Use “Playback sources” consistently at the entry and destination. A source list
contains configured supported sources, not a guarantee of current stream health.
Retain native NavigationLink, List/Form, Picker, Toggle, selection/checkmarks,
press feedback and existing source defaults. Do not migrate or rewrite keys.

**Adaptation/states:** readable same-order groups in one column; useful aligned
columns only at existing wide-window eligibility. Accessibility text uses the
existing stacked labels/accessories. Dark/light and source loading/empty/partial
failure/retry remain distinct. Keep privacy, backup, sync and notification-scope
disclosures in their relevant destination; no recurring engineer text on Home.
FPL's existing notification shortcut and all its code/preferences are unchanged.

**Acceptance:** one label names the source destination; settings never imply
decoded uptime; regrouping preserves every value/route/toggle/default and owner
tools stay secondary. Back navigation and text expansion do not lose state.

## Focused implementation sequence

1. Add small inline context using the existing event/details presentation in
   Home/Search fixture rows and opted-in Matchday rows. No new data feed, player,
   policy or broad navigation rewrite.
2. Reuse the existing `CatalogMatchActionsMenu` for visible Matchday actions;
   keep passive/multi-select `LiveEventCard` consumers unchanged. Check all
   affected channel/fixture consumers and one-action selection semantics.
3. Regroup only existing Settings presentation and harmonize source vocabulary.
   Preserve privacy wording, keys, FPL shortcut and source enablement.

The shared type/badge/layout system is intentionally retained. Long-name fixes
must follow a concrete failing render, not assumptions about an untested phone.

### Source implementation receipt

The three focused changes above are now implemented in existing source files:
`CatalogEventDetailsView.swift`, `SportsDiscoveryViews.swift`,
`LiveEventCard.swift`, `SettingsScreen.swift` and `StreamPluginsSettingsView.swift`.
Home/Matchday `watchEvent`, Search's owner/query flow, source policies, player,
FPL and multi-stream code are unchanged. Cards without an existing Details
callback retain their passive/selection behavior. Inline context only reads
existing schedule/broadcast presentation; its one secondary button opens the
existing full details for richer source options. Save/Remind/Watch owners remain
in the surrounding row.

Four focused regressions were added to `BetaUsabilityTests.swift` and two to
`SettingsUsabilityTests.swift`. Swift frontend parsing of all seven affected
Swift files and focused whitespace checks passed. These are source-stage checks;
test execution, a complete compile and native acceptance are not asserted here.

## Acceptance ledger — not a completed visual gate

| Surface/state | Contract / reference | Evidence now | Remaining gate |
| --- | --- | --- | --- |
| Home current/future + inline context | This contract; retained artwork/Watch hierarchy | Source checked;175 frozen | Candidate native normal/narrow phone and wide/narrow iPad, scroll/press/return |
| Matchday playable saved row | Visible More, grouped personal plan | Source-confirmed hidden-action branch | Native Remove/Details/reminder semantics and exact saved-item persistence |
| Search result/keyboard | Inline context, retained query, direct Watch | Source checked | Native keyboard, focus, query cancellation and result selection |
| Settings normal/failure | Existing controls, task groups, honest labels | Source checked | Candidate native dark/light, accessibility text, menus/back navigation |
| All changed rows | Badge identity, long names,44pt hits | Source checked; no current render claimed | VoiceOver order, Reduce Motion/Transparency, safe areas, resizing |

No compile, source-text test, Catalyst snapshot or historical screenshot closes a
physical interaction/visual gate. Source-stage tests should cover identity-reset,
terminal/unconfirmed/channel presentation, no implicit reminder/lookup actions,
visible menu routes and Settings value/default preservation. Native visual and
physical interaction acceptance waits for the separately authorized next build.

## Apple guidance reviewed24October

[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
supports hierarchy, grouped information, progressive disclosure and adaptive
window/text-size composition. [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
supports revealing relevant secondary information beside its owner. These
inform inline context; the exact row density and three-column phone sport grid
remain Fotty product choices.

[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
informs familiar command labels/grouping; [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
supports readable text, alternatives to gestures, adequate targets and state
communication beyond color.44pt is Fotty's comfortable target convention, not a
claim that every HIG recommendation is an App Review requirement. Current Apple
Markdown versions were read; no new OS API/dependency is needed for this batch.
