# Fotty 2.0.0 (69) — private cold-scroll correction

Date: 2026-09-06. Status: installed and launched on Jelani's iPhone as an
optimized Release build; hands-on scrolling is pending. Jet iPad and TestFlight
build 55 remain unchanged.

## Why build 68 was insufficient

The owner physically rejected build 68 because Home still stuttered. The first
foundation reduced invalidations and main-thread persistence, but inspection of
the lazy-row path found three remaining cold-scroll costs:

- every ordinary row evaluated the catalog-wide CPL channel-fallback resolver,
  even when the event was another sport or already had a playable source;
- a badge view disappearing during a rapid scroll canceled only its SwiftUI
  task, not the underlying coalesced download, leaving an expanding queue of
  work for rows no longer visible;
- the app launched roughly twenty league badge refreshes every process run, and
  their JSON/catalog expansion resumed on the main actor.

## Correction

- The channel fallback resolver is called only for a genuine source-less CPL
  fixture. Normal rows use their existing source path without a full-catalog
  identity scan.
- The badge pipeline reference-counts waiters. When rapid scrolling removes the
  last interested row, the queued URLSession/decode task is canceled. Unique
  loads run at utility priority; shared visible badges still coalesce.
- A valid persisted badge catalog gets a 24-hour freshness window. Existing
  pre-window caches migrate once without launching a refresh during the first
  gesture. Network decoding and league-map construction are nonisolated from the
  main actor. Badge normalization no longer compiles regular expressions per row.

## Verification

- The complete simulator-free Catalyst policy suite and generic optimized iOS
  Release build pass, including new source contracts for cancellation,
  refresh isolation/freshness and CPL-only fallback.
- A signed optimized Release app compiled, passed signature verification,
  installed and launched on Jelani's iPhone. CoreDevice reports Fotty Sports Hub
  2.0.0 (69); the app and Live Activity extension remain present after the hold.
- All owned build/trace roots were removed. Approximately 63 GiB remains free.
  No simulator, UI-test runner, iPad installation or TestFlight upload occurred.

## Remaining acceptance

Cold-close/reopen build 69 and rapidly scroll Home through the catalog. Record
whether it is smooth, improved with residual hitches, or unchanged. Build 69 is
not accepted or eligible for wider beta until that physical result is known.
