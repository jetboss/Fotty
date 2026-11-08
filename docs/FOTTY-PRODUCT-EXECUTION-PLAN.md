# Fotty Sports Hub — private product execution plan

Approved direction: 4 September 2026. This is the current owner-led roadmap,
superseding the sequencing in `NEXT-PHASE-PLAN.md`; historical release records
remain evidence for their exact builds, not for current source.

## Product promise

Find sport worth watching, get into the right broadcast with little friction,
and make better-informed FPL decisions. Success means ordinary daily use without
the owner having to explain controls, find missing matches or correct claimed
facts. It does not mean guaranteeing provider uptime or winning an FPL league.

Keep Fotty Sports Hub private. Keep the accepted F/pitch icon, team badges,
sport-specific character, compact rows with trailing Watch, default dark theme
and optional usable Light/System. This is a connected-workflow improvement,
not another wholesale redesign or a reason to add more tabs.

## Non-negotiable experience

- Home discovers live and upcoming sport across the catalog. Other sports must
  be discoverable without opening every sport filter; no repeated FPL promotion.
- Matchday is the user's plan: followed teams, explicitly saved events and
  opted-in reminders. It is not a second Home or an extra tap before playback.
- A current match that can open a known broadcast opens it in one tap. A channel
  fallback is labelled honestly; it is not proof that a specific match is on air.
- Countdown and reminder belong to upcoming events. Do not show pointless
  bookmark prompts for an immediately watchable event or advertise an empty
  playback destination. Unsupported scores are not an error.
- Provider controls keep working. Never overlay a giant invisible button,
  duplicate unmute control or automatic action that undoes deliberate pause.
- FPL stays optional and dedicated. Published official facts, live projections,
  local plans and model recommendations must remain distinguishable.
- Setup is skippable. Consent, follows and reminders are choices, not hurdles.
- No new subscriptions, paid infrastructure, accounts/social features, tester
  roles, uploads or production deployments are implicit in this roadmap.

## Sequence and completion gates

| Batch | Outcome | Completion evidence |
| --- | --- | --- |
| 1. Protect playback, plans and owner costs | Restrict the native relay; private, bounded paid Coach; persistent unfinished FPL plans and legal combined transfers | Negative-path regressions, native/Worker gates, then separately approved exact-device and production checks |
| 2. One dependable sports journey | Find → follow/save → remind → watch works across Home, Matchday and return routes | Same current event and action across surfaces, failure-state tests and uncoached iPhone/iPad tasks |
| 3. Trust the complete FPL workspace | Every tool uses current relevant evidence; Coach checks the player actually asked about | Rival/deadline/season regressions, named-player and uncertainty evaluation, plans survive refresh and navigation |
| 4. Finish everyday usability | Coherent refresh, browsing position, accessibility, save/recovery feedback and understandable settings | Light/dark and large-text physical checks, successful restore, one received tester report |
| 5. Qualify a meaningful private release | One reproducible candidate and a small ordinary-use round | Exact app/backend identity, entry checks, existing seven-day private protocol, resolved app-controlled blockers |
| 6. Add only useful differentiators | Two or three improvements supported by actual tester friction | Users complete a valuable new task without more clutter, hidden cost or unsupported claims |

### Batch 1 — local implementation, not a shipped release

Implemented after source build 58, alongside the preceding five reliability
fixes. Gate results and remaining boundaries belong in
`audit/Fotty-Foundation-Implementation-2026-09-04.md`.

- Native relay: loopback listener, per-session capability, registered media
  descendants, redirect/destination checks, scoped credentials and bounded work.
- Coach: revocable individual invitation codes, device-local secure storage,
  mandatory configured minute limits, one persisted global daily allowance and
  one cancellable request deadline. No automatic paid retry.
- The owner selected **50 paid attempts per UTC day for the whole group**.
  On-device/deterministic answers do not spend this allowance. Failed or cancelled
  paid attempts can still count; this is not an exact dollar ceiling.
- New checked-in backend configuration stays **paid disabled**. See
  `operations/PRIVATE-COACH-ACCESS.md` before separately approved activation.
- Transfer Lab: manager/season-scoped recoverable working edits, bounded Undo,
  explicit keep/reset after baseline changes and current-baseline save validation.
  Combined route suggestions check the complete resulting squad and budget;
  unknown private selling values remain assumptions.

This closes code-level portions of audit findings 1, 2 and 8. It does not prove
provider compatibility, deployed service privacy, live model quality or physical
restore. No current installed build contains this batch.

### Batch 2 — local implementation, physical acceptance pending

The five items below are implemented in current local source. See
`audit/Fotty-Connected-Sports-Journey-2026-09-04.md` for exact gate results and
remaining uncoached-device acceptance. They are not installed or distributed.

1. Bound and incrementally collect shared-provider discovery so one slow source
   cannot consume all opportunity to find another. Preserve concrete delivery
   alternatives, exact fixture identity and actionable partial failures.
2. Carry Home's current CPL broadcast capability into saved Matchday entries and
   reminder return. Preserve one-tap opening and separate channel rows.
3. Save canonical sport/team identity from onboarding and search. Honor aliases
   without fuzzy wrong-team matches; make selected league preferences meaningful
   or remove their ineffective control. Preserve badges everywhere teams appear.
4. Centralize event status/freshness decisions across Home, Matchday and details.
   Distinguish scheduled time, listed-on-now, decoded playback and checked score.
   Keep saved intent through temporary provider omissions and schedule changes.
5. Make refresh update the complete visible match, with bounded work and honest
   age/error states. Reminder toggles, cancellation and destination routing must
   reflect the actual saved event, not a stale duplicate.

Exit tasks: find a sport without guessing its filter; save tomorrow's match;
recognize a changed start time; open its current broadcast from Matchday; recover
from a provider failure without losing a still-playing source. Test negative
paths and actual state transitions, not just the presence of labels in source.

### Batch 3 — local FPL implementation, acceptance pending

The code-level work below is implemented in local source. Exact qualification
results and limits are recorded in
`audit/Fotty-FPL-Workspace-Implementation-2026-09-04.md`. Nothing is installed,
uploaded or activated by this batch. Existing Plan/Live/Review organization is
retained; no new advanced-tool destination is added.

- Bring Rival Race and all secondary tools into current gameweek/fixture/live
  evidence refresh without competing pollers or erasing working plans.
- Complete chip/wildcard/season and journal target-gameweek boundaries identified
  in the whole-product audit. Legal means the complete move, not isolated pairs.
- Resolve named-player questions before building Coach evidence. Include the
  requested player and relevant alternatives; state missing or private facts.
- Organize existing value around live gameweek, before-deadline decisions and
  post-gameweek review. Do not add yet another advanced-tool destination.
- Evaluate follow-ups, conflicting context, autosubs/doubles, injuries/minutes,
  unavailable evidence and alternative plans. Separate deterministic accuracy
  from model judgment. Run paid evaluations only with explicit allowance.

### Batch 4 — iPhone build 64 web controls accepted; broader acceptance pending

The code-level work is implemented in current source. Private build 64 is
installed on Jelani's iPhone and Jet iPad. See
`audit/Fotty-Everyday-Usability-Implementation-2026-09-05.md` for exact results
and `releases/Fotty-2.0.0-64.md` for current device evidence. Build 64 physically
passes the iPhone web Pause/Play/provider-Play/Sources path; iPad controls and
broader hands-on checks remain. Nothing was uploaded; TestFlight remains build 55.

- Preserve filter/search/scroll and useful workspace state across navigation.
- Finish existing Settings typography, selected accessibility states and theme
  inheritance; keep engineering diagnostics secondary and opt-in.
- Surface save failures at the action that failed. Confirm before replacing
  working data; qualify encrypted backup/restore with a real file and device.
- Test compact and large iPhone/iPad layouts, large text, VoiceOver semantics,
  Light/System, rotation, keyboard dismissal and practical hit targets.
- Make report preparation and actual delivery understandable. Receive one real
  report; a mail sheet opening is not evidence that feedback arrived.

### Batches 5–6 — qualify, then differentiate

Use `beta/PRIVATE-QUALIFICATION-2.0.md`: an owner-selected 3–5-person seven-day
round after exact-candidate entry checks, not an automatic invitation action.
Record completed independently / needed help / failed / provider blocked /
not attempted. Investigate wrong match, lost work, wrong asserted score, hidden
audio and unusable controls before cosmetic preferences.

After that evidence, choose at most two or three: a quick route back to the last
broadcast, opt-in spoiler hiding, a clearer personal upcoming-sports digest,
saved FPL decision alternatives or a useful post-gameweek decision review.
These are candidates, not silently approved features. Background schedule-aware
alerts while the app is closed need a separately reviewed service/cost design.

## Release and operations contract

- Build numbers identify distributed artifacts, not the number of small commits.
  Combine coherent improvements for TestFlight; a narrow cable build is opt-in.
- Tests are simulator-free; reuse one disposable build root, run sequentially,
  record free space and remove generated artifacts on success and failure.
- Preserve dirty/unrelated work. Publication requires a clean, reviewed source
  recovery path; never publish this old-ancestry working tree casually.
- Keep free APIs and bounded scrapers where they are useful. Each dependency
  needs a known identity, freshness, failure and resource boundary, not hype.
- Record deployed backend identity separately from local source, and provide a
  safe paid-Coach disable path. Never solve a provider TLS failure by bypassing it.
- No new analytics service is required: opt-in local diagnostics, exact-build
  notes and received tester reports are sufficient for this qualification.

The next gate is **physical everyday-usability acceptance**, followed by the
meaningful private qualification round only after its blockers close.
Connected-sports and FPL physical acceptance remain open; a source gate is not
proof that users can complete the journey without guidance, that a provider
plays or that paid model advice makes good strategic decisions.
