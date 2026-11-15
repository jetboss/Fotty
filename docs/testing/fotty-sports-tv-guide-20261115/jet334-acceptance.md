# Sports TV guide — consolidated Jet 334 follow-up

## Confirmed on Jet 333 before the repair

The owner unlocked Jet and made it available on 15 November. Normal guide Search and the wide channel/On now/Next layout were inspected in Light appearance. ESPN South’s seven-day sheet linked Bayern Munich–FC Köln on 20 November at 19:30 UTC to the accepted official Bundesliga fixture. Save changed to Remove from My Matchday. Remind displayed Reminder set  / 5 minutes before and stored 19:25 UTC (3:25 PM Tobago). My Matchday contained the saved fixture and enabled bell. Cancelling that test reminder showed Reminder off while preserving the bookmark.

My Matchday incorrectly said that this accepted five-day fixture was no longer in the current schedule: it used Home’s 72-hour projection. Guide Search also retained keyboard focus over the player. A separate Sky Main Event empty-channel result incorrectly used match-specific wording. The guide also duplicated the same future programme because its two titles differed by `vs`/`vs.` punctuation. These four focused app repairs are consolidated in 334; ranking, source opt-ins, transport and playback implementation are unchanged.

## Watch results retained separately

Willow TV1/CS1/CS2 did not pass the stable picture gate. ESPN South TV2 returned 403; Sky Main Event returned no accepted descriptor before player creation. See `guide-watch333-failures.md` and its redacted JSON. These failures are not overwritten by later success and do not establish a guide regression or a common provider outage.

Sky Sports Premier League TV25 did play from normal guide Watch. A 98-second observed hold showed advancing football pictures and the channel watermark, with scoreboard progressing02:26 → 03:36 → 03:59 → 04:12. The app recorded decoded progress about 6.35 seconds after Watch requested. This is a channel Watch pass, not proof of a particular official live fixture or audible commentary. The mirrored screen has no audio relay. No error/replacement UI appeared during the observed hold. Search accessory remained over the player on 333, motivating the focus repair.

## Consolidated repair verification

Final current-source Catalyst run: **396 passed, zero skips and failures**. The earlier 393/394 run is retained: its one failure came from a test helper assigning the same participant ID to Chelsea and Liverpool. The helper was corrected, the refusal assertion retained, and stable-ID label-correction coverage added; production identity matching was not tightened. The first compile overlapped the final channel-copy test addition and is separately retained as invalidated (`sourceUnchanged=false`), never a pass. Normal signed Release 334 compiled successfully, installed on Jet and was independently verified in Apple’s installed-app inventory as 3.0.0(334). Source hashes remain identical to the tested/built candidate. Actual Claude approved the planning/focus, channel-copy and duplicate-presentation changes across three bounded rounds; a final independent read-only review found no material blocker. See `guide334-claude-review.json`.

No phone interaction, source ranking/opt-in change, publication, backend deployment or TestFlight operation was performed.


## Final normal-build 334 physical checks

- **Save and saved planning:** Bayern–Köln appears once in ESPN South’s seven-day sheet. Save changes to Remove from My Matchday and persists into Matchday. The saved row shows Friday 20 November at 3:30 PM Tobago, without the false “no longer in the current schedule” warning. It remains planning-only with no Watch/Check Streams authority.
- **Remind:** enabling displays “Reminder set / 5 minutes before”; the persisted fire time is 20 November 19:25 UTC, five minutes before the official kickoff, not five minutes before the earlier programme start. Cancellation displays “Reminder off”. This verifies scheduling and cancellation, not delivery of a notification five days later.
- **Watch:** normal guide Search → Sky Sports Premier League → Watch channel started TV25. App telemetry measured 7.849 seconds from Watch request to decoded video. Observed pictures advanced for 96.941 seconds, with clocks 30:07 → 30:49 → 31:27 → 31:39 → 31:49. Native continuity recorded 92.825 seconds of media advance over 92.847 seconds, zero stalls/dropped frames, 1280×720, attempt 1. No source switch/error appeared. The search keyboard accessory disappeared before playback, and closing the player retained the query. This is a channel-tune pass; neither live-fixture identity nor audible commentary is established by Device Hub. See `guide-watch334-success.json`.
- **Channel errors:** Sky Main Event still returned no admitted descriptor; its normal Watch alert now correctly says “No playable stream is available for this channel right now.” Retry and dismissal remain available. This is an error-presentation pass, not a source playback pass.
- **Adaptation and cleanup:** the guide and programme sheet were inspected on Jet in portrait and landscape. Jet was returned to landscape Sports TV, Today/All, with an empty query and keyboard capture off. Test-created Bayern bookmark and reminder were removed and later persisted copies verified cleanup. Immediate plist copies can precede UserDefaults persistence; the final delayed copy is the completion evidence.

## Preserved data and remaining limits

The SQLite store, WAL and SHM were byte-identical across installation. The original one saved match remains, with only its normal refreshed cricket `observedAt` metadata changed during the checks. Six existing source/appearance/interest-related preferences compared unchanged. Existing reminder count was zero and returned to zero. Normal caches, diagnostics, recent-channel history and corresponding local sync intents may update through ordinary use; they were not rolled back. No source opt-ins or account links were edited.

The earlier Willow failure/stall, ESPN South 403 and missing Sky Main Event descriptor remain unresolved supply evidence; the investigation did not prove a guide/player root cause that justifies modifying transport, matching or ranking. No current fixture-linked Reviewed TV programme was available for a live programme-Watch test. Future programme Save/Remind and normal channel Watch passed separately. Fullscreen, PiP and independent failover were not rerun because their implementation did not change. No iPhone verification is claimed.

The final focused 396 tests and signed build cover this exact source. Earlier full-guide-suite results belong to the preceding candidate and are not relabeled as a full 334 suite. The remaining live programme, provider delivery and audible-audio gates are not marked passed.
