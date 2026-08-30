# Fotty UI refinement — 27 August 2026

Status: implemented and locally verified. Not distributed; physical-device qualification remains.

This implements the priority refinement direction approved after the [UI audit](Fotty-UI-UX-Audit-2026-08-27.md). It is not a rebrand or a change to FPL scoring, transfer submission, stream resolution, or provider-owned unmute.

## What changed

| Audit area | Implementation |
| --- | --- |
| Readable FPL | Semantic text sizing across the main FPL views; two-line pitch names instead of 7–8-point text; a readable roster from XXLarge upward. The normal pitch remains. |
| Honest labels | Home uses Watch live or Open broadcast according to existing timing. Points carry their actual gameweek and official/live/projected/final status. Missing lineups no longer imply an announcement has not happened. |
| FPL continuity | A root-owned session retains the loaded advisor, workspace, selected tool and per-destination scroll position. Coach draft/pending state, comparison IDs and loaded league state survive main-tab changes. Returning or foregrounding rechecks data through the existing TTL cache; explicit pull-to-refresh remains the cache-clearing action. |
| Difficulty colours | One shared 1–5 palette on pitch/table, explicit difficulty numerals and accessible descriptions. All palette text pairs meet the 4.5:1 regression threshold. The fixture table keeps its team column visible during horizontal scrolling. |
| Recognizable clubs | Preserve unknown club names, using curated abbreviations only where supplied. Match rows wrap names and put actions below match information. Downloaded badge images retain a full club description while remaining decorative inside the labelled badge. |
| Hierarchy | Plan leads with the next decision. At sufficient measured width, supporting evidence sits beside decisions. Tools are grouped by planning, following the gameweek and learning; each destination has a title and All tools action. Matchday shows one relevance explanation and date-groups later fixtures. |
| Clear language | Explain captain rating versus points estimates without altering either. Replace exposed field/algorithm jargon with task language; retain uncertainty and local-draft warnings. Price signal internals remain available in a disclosure. |
| Controls | Selected FPL workspaces expose their state. Home filters retain native picker appearance; amber stays on the app's primary actions and selected navigation. Match/player/source actions use 44-point targets, with compact bookmark artwork. No new video overlay or unmute action. Comparison uses a bounded, searchable player/club sheet instead of a season-sized menu. |
| Settings and feedback | Football, playback and support precede optional local identity. Foreground match updates and scheduled FPL reminders have separate explanations. Feedback has persistent required labels, completion guidance and clear unavailable copy/share actions. |
| Empty states and motion | Live Points links back to Plan; Rival Race links to Mini-leagues. Live Pulse becomes static for Reduce Motion. Live Activity return wording is plain language. |

## Verification

| Gate | Result |
| --- | --- |
| Complete Swift unit suite, final source | 122 passed, zero failures, zero runtime warnings; one explicitly opt-in reference-HLS soak skipped. |
| Home accessibility | All six scopes passed together after the final badge fix: contrast/traits, descriptions, detection, Dynamic Type, hit regions and clipping. |
| Other Dynamic Type audits | FPL's four populated workspaces, Matchday, Settings, Match Center and Player passed. |
| Interaction checks | FPL tool/scroll/search continuity, rapid main-tab/foreground recovery, and native Help/feedback passed. |
| Generic iOS Release and ReviewSafeRelease | Both final-source builds passed with code signing disabled. No archive or upload. |
| Source hygiene | `git diff --check` passed. |

This is 14 distinct passing Catalyst UI checks across bounded runs, with affected scopes repeated after corrections. Some UI runs on macOS 27 beta emitted main-thread responsiveness warnings; this is not a zero-warning UI qualification. The final unit result contains 123 tests including the intentional soak skip, and completed at 18:45 local time.

The strengthened Debug-only fixture includes 15 synthetic players, long names, a five-defender row, captain cards, fixtures and distinct planning/points gameweeks. Its shirt and player-enrichment requests are disabled. The Squad audit now requires a real populated row instead of passing on the empty state.

The interaction check exercises tool and scroll restoration, searchable comparison selection, and returning to the same selected players. An early test selected an underlying comparison button instead of its sheet result; explicit result identifiers corrected the test target. A legacy unit test that expected invented club abbreviations was updated to the approved recognizable-name contract, not removed.

Visual review uses the current-source Mac Catalyst app, not the older installed application. Narrow and expanded Catalyst windows are useful layout evidence, not physical iPhone certification. It caught an initially ineffective wide-layout adaptation and an abbreviated action description; measured-width columns and vertical text expansion corrected them. Attempts to unify Home's native picker tint exposed contrast findings on the beta Mac; an explicit Menu wrapper introduced an unnamed generated child. Those cosmetic experiments were removed, leaving the original native pickers and their selection semantics intact. The audit findings are not suppressed, and description failures now identify their exact element in the result summary. No paid Coach question or live provider stream is needed for this UI check.

## Remaining boundaries

- This is local, unreleased work on the build-33 source baseline. Use the version tool to allocate a higher build before any device/TestFlight distribution. No upload, device installation, commit or push is part of this pass.
- Recheck supported iPhone/iPad hardware: Display Zoom, large text, Coach keyboard, portrait/landscape player targets, daylight, Reduce Motion and a short VoiceOver journey. Widget tint/long-name modes and actual provider playback were not requalified here.
- FPL continuity is implemented; this does not claim that every Home filter or nested Settings navigation path is retained.
- Native Home filter colour unification is deferred. Do not replace platform styling without rechecking contrast, descriptions, selection semantics and large text together.
- Duplicate provider fixtures remain a separately scoped identity diagnosis. UI changes do not resolve missing upstream data or make broadcasts guaranteed.
- Closed-beta task observation is still needed to establish intuitiveness or engagement. Compilation and accessibility automation alone do not establish that the app is premium.

## Resource discipline

All builds and test results reused one owned temporary DerivedData root, with two build jobs, sequential configurations and an exit cleanup trap. No simulator was used. The 1.7 GB final build/test tree and temporary captures were removed after verification; the directory no longer exists and no Fotty/Xcode test process remains. Available disk space was 42 GiB before this gate and 41 GiB after cleanup (39 GiB immediately before cleanup); unrelated system usage was not deleted. Only this small written record and the intended source/memory changes are retained.
