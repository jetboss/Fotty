# Calmer Home UI — local batch, 2026-09-08

Subsequent owner-authorized deployment: private build 82 is installed on
Jelani's iPhone. The device was locked at launch; owner acceptance remains
pending. TestFlight stays 81. See `docs/releases/Fotty-2.0.0-82.md`.

## Scope and release boundary

Implemented the first approved UI batch: Home hierarchy, contextual freshness
notices, and compact shared discovery rows. Build 2.0.0 (81) remains the
distributed baseline. No version change, device install, TestFlight upload,
commit, push, service deployment or tester change occurred.

The accompanying interactive concept uses clearly labelled sample data. Its
broader FPL, Settings, Matchday and two-column iPad arrangements are proposals,
not implemented native screens or live fixture evidence.

## Native changes

- Remove the repeated masthead tagline and interests subtitle. Keep the interests
  edit action in one 44-point-minimum row with its explanatory accessibility value.
- Use quieter continuous discovery groups and slightly tighter rows. Preserve
  actual team badges, sport icons, full-name wrapping, side-aligned Watch and
  opt-in reminders. Large accessibility text retains flexible row height.
- Shorten update warnings. Keep check timestamps behind Update details, labelled
  with the actual source being checked. Keep Retry separately accessible.
- Evaluate CPL uncertainty against the events displayed by Home, Search and
  Matchday, not merely against the existence of CPL elsewhere in the catalog.
- Avoid stacking catalog and football-schedule notices. Do not change source
  freshness windows, receipts or playback eligibility. A retry alone must not
  hide an existing stale-data warning.
- Replace automated notice suppression with explicit fresh, stale-CPL, offline
  and partial fixture states. These test fixtures remain DEBUG-only.

## Verification

Six sequential, simulator-free Mac Catalyst UI checks passed:

1. Stale CPL is scoped to relevant events; update details expand and collapse.
2. Offline notice retains visible matches and Retry.
3. Partial notice retains visible matches and Retry.
4. Home Dynamic Type accessibility audit.
5. Home text-clipping accessibility audit.
6. Home sports filters, activity and full-lineup navigation.

The first stale-state UI run exposed inherited accessibility identifiers on the
notice's buttons. An explicit accessibility containment boundary corrected that;
the passing run exercises independently identifiable Details and Retry controls.

The focused `SportsCatalogRefreshTests` and `BetaUsabilityTests` Catalyst run
passed, including the regression that known stale CPL data remains identified
while a retry is in progress. `git diff --check`, shell syntax and preview
fragment/script syntax checks passed.
The final generic-iOS Release compile also passed with signing disabled. This
is compile evidence, not a signed release archive or physical-device execution.

The interactive concept was inspected at 360- and 736-pixel browser widths,
including dark/light appearance, tab navigation and notification preferences.
This is browser layout evidence, not an iPhone/iPad screenshot or installation.

## Remaining acceptance

On an explicitly selected physical iPhone/iPad, check the new visual density,
long team names, badges, reminder targets, Home interests and contextual warnings.
This batch has not been performance-profiled and does not claim a measured
scrolling-speed improvement. Decide on the wider concept before implementing the
broader native screen changes or combining this batch into a significant release.

All build gates use sequential work and task-owned temporary output with cleanup
on exit. The small interactive concept is a deliberate retained deliverable.
