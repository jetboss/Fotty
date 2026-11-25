# Fotty 2.0.0 (49) - private iPhone badge reliability candidate

Date: 2026-08-31. Status: **installed only on Jelani's iPhone; not uploaded**.
Build 48 remains the newest App Store Connect/TestFlight build.

## Correction

Build 48 decoded opaque live badge tokens with stale obfuscated endpoint bytes,
so valid provider artwork failed across football, baseball and especially
basketball. It could also delay valid ESPN team catalogs behind an optional
slow SportsDB request, while a failed explicit image prevented an already-known
club badge from being tried.

The local build-49 source now:

- constructs the correct provider badge image URL;
- publishes each completed league catalog immediately and retries a fully failed
  cold bootstrap after a bounded cooldown;
- tries unique ordered image candidates so known artwork survives a bad explicit
  provider image;
- expands exact fallback coverage for current football, MLB, college/NFL/CFL and
  rugby names, keeping ambiguous rugby shorthand scoped to rugby; and
- adds a non-retaining current-feed badge-token audit.

## Evidence and hold

- All 164 unique badge tokens in the current 297-event feed returned valid image
  data across football, baseball and basketball.
- Configured/bundled fallback catalogs cover 144/144 current empty-provider
  football names, 30/30 MLB names, 52/52 American-football names and all 16
  current rugby short names.
- Focused regressions pass, followed by the complete simulator-free Catalyst
  unit and generic iOS Release gate. The three-feed football identity audit also
  passes.
- App Store Connect was read before allocation and showed build 48 as latest.
  Build 49 was allocated locally. When the owner asked not to upload yet, the
  in-progress archive was interrupted before verification/export; the upload
  command never ran. Its single temporary root was removed and disk returned to
  approximately 47 GiB free.

## Private installation

After approving a two-lane release policy, the owner requested build 49 only on
the connected iPhone. A single cleanup-controlled Debug device build passed
version, bundle and strict-signature checks, then installed in place over build
48 without an uninstall. CoreDevice independently reports Fotty 2.0.0 (49), and
both the app and Live Activity extension appeared after a normal launch. The
temporary build root was removed; no simulator or UI-test helper was used and
the iPad was unchanged.

This is installation/process evidence, not visual acceptance of Villarreal or
representative baseball/basketball badges. TestFlight remains build 48. Build
49 is consumed as a private device build; any changed shared milestone must use
build 50 or higher.
