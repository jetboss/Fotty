# FPL squad replacement — diagnosis, not a fix

Date: 2026-08-28. Distributed build: 2.0.0 (43).

## Report and scope

The owner reports replacing Pedro Porro and seeing the change fail to persist.
They clarified that the transfer was also made in the official FPL app. These
are two separate data paths; an official save failure has not been established.
This investigation changed no app code, preferences, teams, release or server.

## Confirmed source findings

1. **The imported squad is a public gameweek snapshot, not authenticated current
   team state.** `FPLService.fetchPicksResource` reads
   `entry/{manager}/event/{gameweek}/picks/`. No authenticated `my-team` fetch or
   official team-write integration exists in this path. A newly confirmed
   transfer in the official app is therefore not necessarily visible to Fotty
   before its next public deadline snapshot is published.
2. **A new-gameweek heading can accompany an older squad.** `loadData` chooses
   the next event when the current event is finished. If its picks request fails,
   it fetches the preceding event and sets `picksGameweek` accordingly. The main
   header uses `currentGameweek`, while the Squad pitch is passed the fallback
   picks without a visible last-published-gameweek label.
3. **Valid local edits are stored but then hidden by refresh.**
   `updateUserSquad` validates, updates the displayed picks, sets `isCustomDraft`
   and writes manager/season-scoped `customDraftPicks` to UserDefaults. `loadData`
   always prefers fetched official picks and sets `isCustomDraft = false`; it
   loads a saved draft only if official picks are unavailable. Foreground/return
   calls `loadData`, and `refreshMatchdayData` also replaces the shared picks with
   official data. The Squad pitch mirrors those changes through `onChange`.
   A saved draft can remain on disk while disappearing from the displayed squad.
4. **The immediate-rejection UI is also weak.** The player picker uses a Void
   selection callback and dismisses unconditionally. Squad validation errors
   render in the parent header, potentially above the current scroll position.
   The one-tap transfer recommendation also displays a success banner without
   checking whether its Void replacement call was rejected. The exact replacement
   player and rejection reason in this report are not yet known.
5. **Unsaved Transfer Lab staging is view-local.** Manual selections live in
   `@State stagedPicks` until Save Changes as Draft; view recreation or a shared
   picks update can reset them. This is distinct from the saved-draft overwrite.

## Evidence and limits

- Static path inspection covers `FPLAdvisorViewModel`, `FPLService`, `FPLMainView`,
  `FPLSquadPitchView`, and `FPLTransferHubView`; no iPhone reproduction is claimed.
- At 13:29 AST, a read-only public API probe showed GW1 finished/data-checked,
  GW2 deadline 2026-08-28 17:30 UTC (13:30 AST), and a sampled GW2 picks request
  returned HTTP 404 while its GW1 picks existed. This is time-scoped publication
  evidence, not verification of the owner's private transfer. The Mac's saved
  manager selection also appears in a test fixture and has not been confirmed
  as the owner's phone selection; do not attribute that sampled squad to them.
- FPL's public transfer-history page states that unsigned-in viewers can see
  transfers only through the last deadline:
  [official FPL transfer-history notice](https://fantasy.premierleague.com/en/entry/1/transfers).
- Picks memory cache is 60 seconds; bootstrap cache is five minutes. Explicit
  refresh clears app memory cache, but cannot publish private pre-deadline data.
  Endpoint-specific disk snapshots may also be used after request failure.
- Existing tests cover validation, manager identity and named scenarios, but no
  save-local-squad → successful official refresh → draft-restoration test was
  found. No new build, simulator, live-model request or large temporary output
  was needed for this diagnosis.

## Recommended correction — not implemented

Keep published official picks and persistent local planning picks as separate
state. Live points must use the published lineup, never a hypothetical draft.
Label the published gameweek and explain pre-deadline visibility. Preserve a
valid local draft through refresh/relaunch and reconcile after a new official
snapshot, without silently deleting user intent or treating a local change as a
verified official transfer. Use explicit commit outcomes and show validation
errors inside the player picker; never dismiss or display Saved on rejection.

Add save/relaunch/foreground/network-refresh/manager-switch regression cases,
including fallback to the previous event, deadline publication and rejected
transfers. Direct pre-deadline official sync would require a separately approved,
supported authenticated integration; do not collect passwords or session cookies
as a workaround.
