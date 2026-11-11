# Apple UI baseline

Source review: 2026-09-19. These are short design decision aids, not a frozen copy
of the HIG or an App Review certification. Reopen relevant official guidance when
the target OS, component behavior, or a material design decision changes. Verify
deployment-target availability in API documentation before adopting new controls.

## Purpose and hierarchy

[Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
and [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)

Lead with what people came to do. Limit competing controls; make secondary actions
discoverable. Preserve context as presentation changes. Use purpose, simplicity,
agency and craft to choose between alternatives rather than adding decoration.

## Layout and iPad adaptation

[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

Use safe areas, aligned groups and readable content widths. Account for resizable
iPad windows, not just device model or full-screen orientation. Use additional
width for useful composition; readability may still justify bounded text columns.
Avoid needless layout switching as a window resizes. Review text expansion and
keyboard effects alongside portrait/landscape layouts. Exact breakpoints and grid
counts belong to the product's tested layout contract, not an assumed HIG rule.

## Typography

[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

Prefer system text styles and preserve hierarchy as text scales. Apple lists
17 pt default and 11 pt minimum guidance for iOS/iPadOS; those values are not a
reason to make primary content 11 pt or hardcode all text to 17 pt. Use meaningful
roles, readable weights and appropriate wrapping. Don't silently cap accessibility
sizes to protect a rigid composition. Custom fonts need equivalent scaling behavior.

## Color and materials

[Color](https://developer.apple.com/design/human-interface-guidelines/color)
and [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

Use color meanings consistently. Prefer semantic system colors where appropriate;
custom palettes need appearance and increased-contrast variants. Judge legibility
over the actual material and content. Liquid Glass is a functional navigation and
control layer, not a treatment for every content card. Let standard controls adopt
platform materials; custom effects need a purpose and a supported-OS fallback.
Respect system settings rather than imitating glass with fixed blur/opacity.

## Navigation and actions

[Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
and [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

Tabs represent stable destinations, not actions, and should preserve their context.
Assess native iPad tab/sidebar adaptation for the actual hierarchy; don't impose a
sidebar on every app. Label actions predictably. Related choices should have
coherent sizes; prominence comes mainly from style. Custom buttons need press
feedback. Apple's general button guidance uses at least a 44 × 44 pt hit region;
the accessibility page also distinguishes platform default/minimum control sizes.
Treat 44 pt as a comfortable project baseline, not a blanket App Review statute.

## Accessibility

[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Review Dynamic Type, VoiceOver labels/values/order, color-independent cues, contrast,
spacing between controls, alternative ways to perform gestures and keyboard access
where relevant. Check Reduce Motion and Reduce Transparency. Static screenshots
cannot establish these behaviors; use interaction evidence. Use Accessibility
Inspector when available, but passing its checks does not certify the full journey.

## Loading and motion

[Loading](https://developer.apple.com/design/human-interface-guidelines/loading)
and [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

Show a response promptly and allow useful interaction while content loads. Use
determinate progress only when progress is known; don't fabricate percentages.
Motion should clarify action or continuity and shouldn't delay use. Prefer system
motion for system controls. Custom characterful motion needs an equivalent reduced
motion state and should not repeat unnecessarily during routine browsing.

## Local acceptance checklist (our engineering convention)

For the changed surfaces, cover representative cases rather than claiming every
device from one screenshot:

- Normal phone width and a width/text-size stress case with long content.
- Wide and narrow iPad windows when the change affects tablet composition.
- Light/dark appearance and relevant contrast/transparency preferences.
- Accessibility text plus VoiceOver/focus and actual touch behavior.
- Loading/empty/error states and keyboard state where applicable.
- Navigation away/back, repeated action, and resize without unintended state loss.

Capture device or window, OS/build, appearance, text size, content state, observation
and remaining gap. Changes to rendering or scrolling require measured performance
evidence before claiming improved smoothness. This checklist is not an Apple
requirement to run every case for every copy edit.
