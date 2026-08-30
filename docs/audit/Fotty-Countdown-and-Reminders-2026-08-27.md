# Scheduled starts and opt-in reminders

Owner approval: “ok proceed i love the opt in idea.”
Candidate: 2.0.0 (41), following physical checkpoints 39–40. TestFlight remains 35. Physical testing is limited to the
normal iPad app under the owner's existing diagnostic authorization.

## Product contract

- Upcoming events show **Starts in**, not a promise that a provider becomes
  available at that time. Hours/days are compact; the final five minutes show
  minutes and seconds. A listed broadcast becomes explicitly tappable at two
  minutes before the start; at the scheduled time it says Watch. Fresh official
  live status can override catalog timing. Stopped/postponed status overrides
  a countdown. Channels and unknown start times never get fabricated timers.
- **Remind me** is an explicit device-local opt-in for five minutes before the
  scheduled start. It also saves the event in My Matchday. Bookmarks/follows
  alone do not schedule these reminders. The filled bell cancels the reminder
  without removing the bookmark; removing the bookmark also cancels its reminder.
- The unselected reminder action disappears once its five-minute deadline has
  passed. A delayed permission response is checked again against the clock;
  no overdue/immediate replacement notification is silently generated.
- Reminder taps open the matching saved event at the top of existing My
  Matchday, not an extra details screen or an automatically playing stream.
  A dismissed notification does not navigate. Unknown/removed targets explain
  that they are no longer saved instead of inventing a match or stream.
- Provider lookup failures stay inline with **Not ready · Retry**. No empty
  player is presented; the next explicit retry makes a real lookup. Normal
  source playback, startup grace, provider controls and failover are unchanged.
- After seeing build 40, the owner approved compact rows: teams/badges left,
  Watch right, and no persistent bookmark competing with playback. Saving and
  removal use the native long-press menu and accessibility actions; future
  countdowns and the opt-in bell stay visible. Only narrow space/accessibility
  text stacks controls. Compact Retry uses the full-width failure explanation;
  reminder results and permission guidance also span the full row.

## Implementation and safeguards

- `MatchStartPolicy` is shared by countdowns and guarded Home/Matchday/Match
  Center actions. MultiView's pre-start window is also two minutes. Resolved
  catalog metadata is checked again before starting a source lookup.
- `MatchStartControls` updates only its local visible UI: once a minute for
  distant starts, once a second in the final five minutes, with no API calls
  or stream probing. It handles narrow/large-text layouts and semantic themes.
- `MatchReminderStore` persists explicit selections with stable request IDs.
  Absolute UTC calendar triggers include seconds and do not repeat. Notification
  payloads carry only the local match route and timestamp, not stream URLs.
- A serialized system-notification queue and per-event revisions protect
  permission/add/reschedule responses from resurrecting cancelled opt-ins.
  Native notification permission is requested only after explicit opt-in.
  Permission denial or a scheduling error is not presented as success.
- Only exact fresh catalog IDs update snapshots; missing rows are not evidence
  of cancellation. Existing football schedule/status refreshes revoke known
  postponed/cancelled/finished/already-live reminders. Learned catalog time
  changes replace the same request. Unknown new times revoke the old request.
  Root foreground checks do not overwrite snapshots with source-less disk-cache
  rows. No new data poller, subscription, server or model request is introduced.
- There are at most 32 active match reminders, with additional total-pending
  checks reserving capacity for FPL/other alerts. Reconciliation only removes
  the match-reminder namespace; it never deletes FPL or goal-alert requests.
- Native Help distinguishes these scheduled reminders from foreground-only
  followed-team score alerts and from FPL deadline reminders.

## Verification

Final-source qualification and physical outcomes are recorded in
`docs/releases/Fotty-2.0.0-41.md`. Build 39's
real iPad check caught future names being dimmed by a disabled parent button;
40 renders those names as plain information and tests the actual Home row.
Build 41 restores compact action geometry and moves saving into a secondary menu.

The new deterministic suite covers exact timer/play boundaries, channels and
unknown/source-free fixtures, stopped/live precedence, timer cadence, UTC
notification contents, silent saves, persistence/de-duplication, permission
denial/late acceptance, cancellation during permission/add/reschedule, earlier
and later reschedules, missing feeds, elapsed triggers, permission revocation,
capacity isolation, removal/retry, route selection and direct-action guards.
Normal, light/dark and narrow accessibility-layout components are rendered with
a nonblank-image assertion. These previews do not certify physical Dynamic Type.

## Explicit limits and remaining device acceptance

- The OS can deliver a scheduled local notification while Fotty is closed;
  notification permissions, Focus and system settings can silence or delay it.
  Fotty cannot learn a last-minute reschedule while closed. The dated CPL
  snapshot is not a live schedule feed; no broader update guarantee is implied.
- Exact catalog-ID changes and a provider silently disappearing are not safe
  evidence of cancellation. Fuzzy team matching must not cancel another game.
- An iPad process hold and screenshot do not prove an actual bell tap,
  five-minute delivery while locked, notification-tap return, or cancellation
  on that device. Record those interactions separately when exercised.
- No simulator, device UI-test helper, iPhone install, TestFlight upload,
  new tester invitation, Git publication or remote deployment is in scope.
- Keep one temporary build directory with a cleanup trap. Remove all owned
  build/test/capture output after verification, including failures.
