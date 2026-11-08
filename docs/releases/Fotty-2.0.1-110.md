# Fotty Sports Hub 2.0.1 (110)

Prepared and installed privately on 2026-09-20. Status: **catalog clarity and
CPL playoff-identity correction running on Jet iPad**. No TestFlight or Worker
deployment is included.

## Scope

- Keep partial responses from redundant catalog mirrors as internal telemetry;
  they are not proof that a user-visible broadcast is missing. Failed refresh
  and stale CPL schedule warnings stay visible because they are materially
  different conditions.
- Name an active sport in Home's empty state and offer `Show all sports`, so a
  retained Fight filter cannot look like an empty global catalog while Football
  has live matches.
- Preserve both the playoff stage and confirmed participants in the CPL manifest,
  Worker policy and iOS model. The reviewed 20 September final is Antigua &
  Barbuda Falcons vs Jamaica Kingsmen and is labeled `CPL Final`.
- Render an unresolved future playoff round as one honest stage event without
  fake team badges or `Teams to be confirmed` as an opponent.
- Reconcile old on-device stage-only receipts with known participant identity
  while retaining a newer verified kickoff time.

## Verification

- All 141 web/Worker unit tests pass.
- Complete simulator-free iOS CI passes, including Catalyst units and generic
  iOS Release compilation.
- Focused Swift checks pass for silent partial-mirror telemetry, stage-only rendering,
  resolved Final identity, complete manifest parity and cached-stage regression.
- The signed optimized physical-device gate passes. CoreDevice reports 2.0.1
  (110) and both Fotty and its Live Activity extension running on Jet iPad.
- An exact-build 2360-by-1640 iPad screenshot confirms Fight selected, Football
  reporting seven live events, the filter-specific empty state, `Show all sports`,
  and no routine partial-mirror banner. Owner tap acceptance and inspection of
  the Final after selecting Cricket remain open.
- Temporary build roots and screenshots were removed; free disk remains about
  58–59 GiB.

## Acceptance boundary

Browse Sports remains where it was. The recommended next UI decision is a compact
sport picker near the masthead while retaining the full artwork grid below the
schedule, not moving the entire grid ahead of live/upcoming matches. The updated
Worker source is not deployed, and no TestFlight, iPhone, tester, commit or Git
publication action occurred.
