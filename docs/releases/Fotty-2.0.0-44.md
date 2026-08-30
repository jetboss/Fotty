# Fotty 2.0.0 (44) — private iPhone FPL draft correction

Status: installed on the owner's iPhone only, 2026-08-28; physical interaction
acceptance remains open.
TestFlight remains 2.0.0 (43), independently checked before allocating 44.

## Scope

The owner approved fixing the diagnosed FPL squad persistence issue and installing
only on their iPhone. Small scoped changes are privately validated first; shared
fixes are later batched into an explicitly released TestFlight build. No tester
notification/settings changes, iPad installation, simulator, device UI-test helper,
Worker deployment, paid Coach request or Git publication is authorized here.

## Changes

- `officialPicks` and its published gameweek are separate from the editable
  selected squad. Full/foreground and live refresh use the same draft-restoration
  transition. Older fallback responses cannot roll back a newer published week.
- Saved draft context retains its target/base week and budget. The original
  manager/season array remains readable by build 43; edits made by that older
  build supersede stale companion context. Viewing published picks does not
  delete the draft, and the selected source persists across reopening.
- A compact source notice explains public deadline visibility and offers
  published/draft switching. Generated-draft replacement requires confirmation.
- The picker preserves FPL position and stays open with an error on rejection;
  one-tap transfer recommendations no longer report a rejected save as success.
- Live totals/autosubs use only matching-gameweek published picks; local drafts
  carry no official points history, active chip or automatic substitutions.
  Published captain/bench facts identify their actual gameweek. Model advice
  labels its draft source and never attaches published/live multipliers to it.
- After the owner questioned Alexander-Arnold appearing in test output, confirmed
  it was a Debug-only UI fixture name, not a live FPL catalog entry (fresh official
  feed returned no Trent/Alexander-Arnold match). Replaced real-player fixture
  names with explicitly synthetic names while retaining long/hyphenated layout
  cases. Normal device launch does not enable this fixture.

## Verification

Final-source qualification:

- Mac Catalyst unit suite: 200 passed, zero failed, one opt-in reference-HLS soak
  skipped; no unit runtime warnings. Nine new draft/publication/validation tests
  cover restoration, manager isolation, old-build compatibility, scoring and
  Coach boundaries.
- Three scoped Catalyst UI checks passed: saved-draft/picker rejection,
  workspace Dynamic Type, and context retained across tab switches. Existing
  beta-Mac main-thread warnings remain in UI results; these are not claimed
  warning-free or physical-iPhone interaction evidence.
- Existing Worker Coach-contract/scoring suites: 24 passed; no network or paid
  model request. No Worker change or deployment.
- Generic iOS ReviewSafeRelease and normal signed Debug builds passed. App and
  extension independently report 2.0.0 (44); strict deep signature validation
  passes. The installed artifact is normal Debug, not Review Safe.
- Final source/config/test fingerprint:
  `2bcf3616b6fef00d1a2c9d2b395d983e3f76f8e14df611d724086aade59f2403`.
  Signed iOS executable SHA-256:
  `4000acfb97791cdd9774caa3f8c34d530f006d752dea80e0f1effd6345ef52e7`.

Tests use isolated preferences and synthetic football data; they do not change
a private official FPL account. Initial test compilation found an Encodable-only
helper assumption for a Decodable DTO; the fixture was corrected without changing
the production API model. The new UI test initially needed harness corrections
for Catalyst alert identification and searching within an open picker. Final
runs use fictional fixture names and pass; those initial harness failures are
not attributed to production save behavior.

At 14:11 AST, a scoped read of the connected owner's iPhone preferences and
that manager's public GW2 picks returned 15 saved local players and HTTP 200
published picks; Pedro Porro was absent from both. This is fresh evidence for
the actual connected phone, distinct from the unconfirmed Mac sample in the
original diagnosis. No manager ID, raw preference contents or private team data
is retained in this report. The temporary preference copy is part of gate cleanup.

### Owner's iPhone

CoreDevice installed the signed normal app in place, without an uninstall or
container reset. Independent installed-app reads report 2.0.0 (44) on the
iPhone 15 Pro Max / iOS 27.0. An argument-free normal launch survived the
20-second process hold. No physical UI-test helper was installed.

Scoped before/after preference comparisons verify that the linked manager,
15-player saved local draft, appearance and saved matches are unchanged. New
draft-context/source-choice keys were absent in both snapshots; no retention
claim is made for absent settings or an uninspected SwiftData store.

The legacy screenshot transport could not discover this phone over either
USB or its network option. A diagnostic Squad-route launch also failed argument
validation; it is not visual or touch evidence. The successful normal launch
and independently verified installation remain valid. No fake fixture was
enabled on the phone, and no user's squad selection was changed by testing.

## Acceptance and limits

The owner still needs to verify the displayed replaced defender,
refresh/reopen persistence and published/draft toggle on the phone. A process
hold is launch evidence, not proof of these taps. Public FPL publication still
controls when official-app transfers become visible. Unsaved Transfer Lab staging
still requires Save Changes as Draft. Device-local storage is not cloud sync.

## Storage

Before qualification: 62 GiB free. One bounded temporary DerivedData root with
an exit/interruption cleanup trap is used for all sequential tests/builds.
After installation/evidence checks, the trap removed the complete 1.4 GB owned
gate, including duplicate signed apps, result bundles, diagnostic attachments,
logs and all temporary iPhone preference copies. No task-owned Catalyst process
remained. The exact root was independently verified absent; post-cleanup disk
reports 61 GiB free. No archive, simulator or device UI-test helper was created.
