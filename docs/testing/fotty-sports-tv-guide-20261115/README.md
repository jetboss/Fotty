# Sports TV guide — source implementation

## Scope and reference

Owner authorized the Sports TV guide first on 15 November, following the approved iPhone/iPad preview. Source ranking, player Up next, pitch, devices, cloud and TestFlight are outside this gate. Base is released/private build 332 source, `7f5c8dc`; implementation is isolated from the owner's primary checkout.

Reference: `fotty-guide-up-next.html`, SHA-256 `d7fa26aa6efe429b10e36f57d35c579ad4cba33b7aa875a4df529fa5a98c65ae`. Actual Claude approved that concept in the separate preview review. The guide uses native navigation, search, pickers, menus, sheets and semantic text. Existing favourites/recent/language ordering is preserved; programme cards replace the channel-only copy. Wide layouts have channel/On now/Next columns, narrow and accessibility layouts stack. Today/Tomorrow use the local calendar. A station's full guide sheet preserves the existing seven-day schedule horizon.

## Behaviour contract

- A current programme needs its existing fresh programme authority. A scheduled time never means LIVE or verified playback.
- Only an explicit fresh, unique registry fixture link plus the current canonical catalog supplies match Watch, Save or Remind. All actions use existing stores/coordinator. Generic guide rows tune the channel and never infer a match from names or a channel's typical sport.
- Future linked programmes can use Save/Remind after exact fingerprint validation, without moving the playback clock forward or admitting future playback.
- Linked Watch uses the existing match source flow and existing ranking. It does not promise to force the displayed TV station. Direct channel Watch retains its existing path and recent-channel recording.
- Links are revalidated on actions; expired or conflicting links cannot survive through a retained sheet. A detailed unbound schedule duplicate cannot suppress the original explicitly linked row or inherit its identity.
- Immediate Opening feedback and cancellation continue to come from the existing viewing session. Guide refresh keeps the existing bounded interval and foreground lifecycle.
- No guide information still leaves the direct channel action available. Empty guide, no search results and no favourites are different states.

## Verification

- Full Catalyst suite after the main implementation and first review repairs: **2,711 passed, 12 existing skips, zero failures** (2,723 executed). [Receipt](validation.json).
- Final compile and **131 focused tests passed, no skips/failures**, covering guide policy/presentation, reminders, inline reminder feedback and background reminder refresh after the last search/error fixes. The final typed Willow pregame regression is included. All six compiled product/project/test file hashes stayed unchanged throughout this gate and match the committed sources. [Receipt](validation-final-focused.json).
- First run retained separately: one new test incorrectly expected an unattached Catalyst semantic-font measurement to grow at an accessibility setting. That host reported equal heights. The corrected local test checks containment/wrapping; the strict growth assertion remains for iOS. This is a measurement limitation, not a physical iOS pass. [First receipt](validation-first-run.json).
- Actual Claude subscription CLI reviewed three bounded rounds and approved the final source. Findings repaired: expired reminder admission and implicit Save, lost direct channel fallback, VoiceOver programme identity/time, sheet-local errors/dismissal, and multi-word/diacritic-insensitive search. [Review](claude-review.json).
- Native component renders inspected for narrow phone and wide iPad layouts, light/dark appearance and long cricket names. Representative illustrative renders: [phone](native-renders/phone-dark.png), [iPad](native-renders/ipad-light.png). These are local component renders with sample programmes, not full-screen/device/live-match evidence. ImageRenderer does not establish system-control animation or physical text scaling.
- Xcode membership comparison adds the new test exactly once, with no new errors. The 45 existing intentional retired-FPL exclusions still trigger the older broad membership script; this task does not re-enable them. Its 32 tooling tests pass. [Comparison](membership.json).
- Both test gates removed owned DerivedData, apps, raw logs and result bundles; final free disk was over 28 GiB. No simulators, device interaction, app installation, source-setting mutation, cloud change, Git publication or TestFlight action.

## Jet installation follow-up

The owner subsequently authorized Jet-only installation and Watch/Save/Remind checks. The real metadata preflight exposed and repaired two future-planning gaps;152 additional focused tests and an independent Claude review passed. See [the Jet333 acceptance record](jet333-acceptance.md) for exact installation and physical-check status. Phone and TestFlight remain excluded.

## Remaining validation and deliberate boundaries

The original source gate did not exercise physical interactions, larger text, VoiceOver focus, notification-permission presentation or real Watch playback. The later Jet-only gate is recorded separately above; the phone remains untouched. No release readiness claim is made. Player Up next and pitch remain outside this guide-first task. Source ranking and provider admission/transport are unchanged.

The fixture-linked path requires an explicitly published association and a current canonical fixture. Start-only generic schedules never gain match identity from a similar title. When a source advertises an exact programme start after official kickoff, the existing future-identity policy can temporarily omit fixture actions until that programme begins; direct channel Watch stays available. This retained edge was reviewed as nonblocking and was not used to relax playback eligibility.

The phone layout deliberately preserves existing personal channel grouping while using programme-led cards; wider iPads use channel/On now/Next columns. The full station sheet retains the seven-day guide beyond the Today/Tomorrow overview. Generic programmes visibly say Watch channel; linked Watch uses the existing match-wide source selection rather than promising the displayed station.
