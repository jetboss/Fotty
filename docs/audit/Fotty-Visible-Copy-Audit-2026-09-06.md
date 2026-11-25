# Fotty visible-copy audit

Date: 2026-09-06

## Outcome

Fotty's primary screens now lead with the action, state or recovery choice a
user needs. Repeated explanations and implementation vocabulary were removed
from Home, Search, My Matchday, Match Hub, playback, Settings and the FPL
workspaces. The audit reduced direct `Text`/`Label` literals over 90 characters
from 64 candidates to 29. The remaining long copy is concentrated in consent,
privacy, destructive backup restore, provisional scoring and recovery contexts
where shortening further would hide a real boundary.

## Changes

- Home and personalized empty states say what is missing and how far ahead was
  checked without discussing provider catalogs or repeated timing rules.
- Search, Match Hub and broadcast selection use `match`, `channel`, `broadcast`
  and `option` instead of `catalog`, `global source`, `provider` and `snapshot`.
- Playback loading and terminal errors are shorter and no longer expose startup
  windows, local handshakes or recovery implementation.
- My Matchday removes repeated section subtitles and the permanent reminder
  explanation; its empty states explain how to populate the screen.
- Settings keeps privacy, data-loss and credential warnings but removes repeated
  explanatory paragraphs and simplifies the feedback workflow.
- FPL keeps evidence labels and official-FPL boundaries while removing the same
  disclaimer from every tool. Data provenance is presented as `Official FPL
  data` or `Saved FPL data`, not cache/network terminology.
- The existing test contracts were updated to assert the retained meaning—local
  plans and estimated current prices—rather than deleted wording.

## Content rule

Visible copy should earn its space by doing at least one of these jobs:

1. name the current state;
2. tell the user what action is available;
3. explain how to recover;
4. disclose a material privacy, cost, destructive-action or data-accuracy limit.

Detailed education belongs in Fotty Help. Accessibility labels and hints may be
more explicit than the visual surface and were not removed merely to reduce
literal counts. Localization is a separate follow-up after this English copy is
stable; this pass did not introduce a new string-catalog migration.

## Verification

- `git diff --check` passed.
- The complete simulator-free unit suite and generic iOS Release compile passed.
- Ten focused Mac Catalyst UI checks passed: Dashboard clipping, element
  descriptions and Dynamic Type; FPL, Matchday, Settings, Match Center and
  player Dynamic Type; native Help/feedback; and Home discovery.
- No simulator, physical-device UI-test runner, device install or TestFlight
  upload was used for this source pass.

