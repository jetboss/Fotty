# Shared official-fixture catalog and one-tap Watch

Owner approval29October2026: build a shared catalog from official fixtures and
all enabled reviewed sources, fix matching, then test privately. Owner changed
the physical target to Jelani's iPhone because Jet iPad is in use, and explicitly
approved enabling CS on that phone. Keep FPL/multi-stream unchanged; no TestFlight,
Git publication, cloud deployment, new feeds/accounts/spending or security changes.

The owner subsequently rejected the visible Check streams workflow. The product
acceptance is one normal Watch action: immediate feedback, automatic source
resolution, first valid source starts, late alternatives append to the same
player. Countdown/terminal/identity/opt-in rules remain authoritative. Users do
not operate a diagnostic lookup step.

## Implementation ownership

- MatchListViewModel.sourceCatalogRequests: accepted official fixtures, existing
 14day Search planning horizon, current retained fixtures, max256 identities.
  Provider catalogs cannot add fixtures or mark them LIVE. Existing provider-only
  browsing rows remain preserved; reviewed official competition coverage unchanged.
- FixtureCatalogAvailabilityIndex in StreamDiscoveryCoordinator.swift: separate
  metadata-only, provider-namespaced listings, unverified/conflict/failure/absent
  outcomes and generation/identity/expiry/enablement guards. No media URLs or
  StreamSessions. Catalog matches do not authorize Watch playback by themselves.
- Each source actor.catalogMatches: one logical bounded cached catalog read per
  relevant scope, parsed once and matched to many fixtures; no bulk stream/meta
  retrieval. Existing Watch resolver revalidates exact current descriptors.
  CS/AS/FS/SV isolate ordinary sport/genre failures; safety/cancellation remains
  fatal. CNC retains NHL-only undated hints; Score808 retains its late window.
- FixtureSourceCatalogCollector in LiveCatalogSnapshot.swift: all7 curated
  definitions, enabled sources only,2 concurrent metadata lanes,45s common owner.
  Tickets/budgets reserved only when a lane actually starts with its current clock.
 300s automatic cadence,96 logical snapshots/provider/24h and24/1h. No row networking.
- MainTab foreground owner: source changes restart/revoke; fixture publications
  replace exact keys without cancelling unaffected transport. Refreshing metadata
  does not change source settings, preferences or an already mounted player.
- Primary evidence derives from the accepted current raw provider response,
  never retained old browsing rows stamped with a new partial-response receipt.
- Core UI uses shared availability consistently. A fresh scheduled match may
  receive a manual playback attempt while official LIVE status lags, if an exact
  fresh source listing exists; its status remains scheduled. Upcoming countdowns
  and accepted terminal facts win. Source uncertainty is not fixture truth.

## Verification and current gate

The initial shared-catalog/source gate passed431 tests,0fail,4 intentional live/
physical skips. A final advancing-clock correction then passed52 focused catalog/
index/admission tests with0fail/skip. These are current-source Catalyst tests,
not testing the old installed Mac app and not decoded live-stream proof.

Signed private188 was installed/launched on the authorized iPhone, with its35
preference keys backed up privately. No iPad interaction beyond availability
inspection. The188 UI still exposed Check streams; the owner rejected it.
The one-tap Watch refinement passed124 focused tests,0fail/0skip. Signed private189
compiled/signed and installed in place. Installed version189 is confirmed. The
foreground app was left alone; the owner is using the phone in another app.

Post-install preferences show CS already ON (all7 reviewed modules ON); no agent
toggle performed. Preserve current choices. Remaining: normal-device
catalog/fixture/Watch checks. Use only fresh current real
fixture/programme evidence for a live player/fullscreen/PiP gate. Current Tests at
Stumps are not active-play pins. No reused finished Cup fixture. PL/UCL/cricket
independent-delivery acceptance remains separate from catalog metadata success.
