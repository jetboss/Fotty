---
name: apple-ui-design
description: Design, audit, and refine native iOS and iPadOS interfaces using current Apple Human Interface Guidelines, adaptive layouts, accessible interactions, and reference-to-build visual verification. Use for native screen design, UI polish, design systems, or critique; not backend work or generic websites.
---

# Apple UI Design

Produce an interface whose hierarchy, interactions, and adaptation feel native,
while retaining the product's identity. A successful build is not visual acceptance.

## Establish the design contract

- Respect the requested mode: critique, discuss, preview, or implement. Improving
  design guidance does not authorize editing the product. Installation and release
  remain separate gates.
- Read the project's design guidance and inspect the current screen/components.
  Label historical screenshots as historical. If current visuals are unavailable,
  give a source-based assessment with visual acceptance open; do not invent a view.
- Identify the user's main task, the information needed for it, the primary action,
  and the specific friction. Preserve explicit preferences and accepted behavior.
- Read [Apple baseline](references/apple-ui-baseline.md). Open the relevant current
  Apple pages before a major design decision; check API availability separately
  before implementation. Distinguish HIG advice, actual API/platform constraints,
  and project choices. Never promise App Review approval from a HIG checklist.
- If current documentation or screen access is unavailable, a discussion may use
  the dated baseline and supplied evidence provisionally. State what needs fresh
  verification before implementation; don't block useful conceptual feedback or
  present it as an observed native result.

## Design before decoration

For a substantial change, make a short screen contract before writing UI code:

1. **Priority:** first useful information, primary action, secondary destinations,
   and anything being removed. Don't fill an empty space with an invented feature.
2. **Composition:** header, content groups, controls, reading order, spacing rhythm,
   alignment, artwork scale, and intentional use of available width.
3. **Adaptation:** compact/wide phone, narrow/wide iPad window, accessibility text,
   long names, safe areas, keyboard, and orientation. Reflow rather than shrink.
4. **States:** relevant loaded, empty, loading, failure, unavailable, selected,
   pressed, and disabled states, plus recovery and back navigation.
5. **Acceptance:** reference artifact, important visual invariants, interactions
   to verify, and what current evidence can actually establish.

For a small localized adjustment, keep this proportionate; don't require a new
mockup or broad audit. For an unapproved substantial redesign, show a meaningful
direction before broad implementation. Sample data must be marked as illustrative.

## Native structure, product character

- Prefer appropriate system navigation, sheets, forms, menus, buttons and media
  controls. Custom appearance must not lose their semantics or expected behavior.
- Give tabs distinct purposes and preserve context on return. Don't turn an action
  into a destination merely to justify a tab, or introduce an extra screen for an
  action that can complete in place.
- Keep related choices visually coherent. Establish primary/secondary emphasis
  through hierarchy and style, not arbitrary oversized controls.
- Use a small semantic vocabulary for typography, spacing, surfaces, radii, and
  actions. Inspect and extend existing tokens before creating another theme.
  A spacing scale is a product convention, not an Apple-mandated numeric grid.
- Use platform symbols for familiar actions; preserve meaningful brand art,
  badges and custom illustrations. Match optical size, alignment and visual weight
  across the entire asset family, not just the first few visible items.
- Keep decorative depth subordinate to content. Don't equate premium with extra
  glass, gradients, shadows, tiny text, empty space, or more animation.

## Interaction and accessibility are part of the design

- Prefer semantic text styles and genuine Dynamic Type behavior. Don't use
  aggressive scaling or ellipses to hide a layout problem or essential identity.
- Keep compact visible controls comfortably tappable. Use 44 × 44 pt as the
  usual iPhone/iPad touch-target baseline; inspect the actual hit region and
  overlapping targets, not only the drawing's frame.
- Use real Button/Toggle/NavigationLink semantics where appropriate. Provide
  visible press/selection/disabled feedback and useful accessibility labels,
  values and reading order. Don't encode status in color alone.
- A tap should register visually before slower work completes. Loading must not
  obscure cancellation, trap navigation, or restart simply because a view redraws.
- Keyboard appearance must not hide the reply, input, or submission action.
  Test focus and dismissal rather than adding a blanket tap gesture that swallows
  child controls. Preserve navigation and draft state when appropriate.
- Design light and dark variants intentionally. Check actual foreground/background
  contrast, Increase Contrast and Reduce Transparency, not just hex tokens in
  isolation. If claiming a numerical contrast result, name the method and context.
- Use brief purposeful motion, with a Reduce Motion alternative and no extra wait
  before interaction. Keep nonessential looping animation out of scrolling lists;
  verify performance when changing rendering or update frequency.

## Implement and compare honestly

- Preserve data truth and business behavior during polish. Flag discovered
  functional issues separately; don't silently change scheduling, permissions,
  scoring, source eligibility, playback ownership, or security to fit a mockup.
- Inventory shared component consumers before changing them. Audit affected
  secondary screens and sheets, not just the landing page.
- Compare the reference and actual native render at equivalent window size, text
  size, appearance and content state. Inspect hierarchy, placement, dimensions,
  type, imagery, density and interactions; colors alone are not fidelity.
- Record meaningful differences as intentional adaptations or unfinished work.
  Don't force literal reference geometry when it harms accessibility/native use;
  explain the adaptation and verify it.
- Report evidence separately: concept preview, source inspection, compile/tests,
  native visual inspection, physical interaction, and user acceptance. An old Mac
  app, browser mockup, launch hold or passing UI test is not current iPhone proof.
- Use only authorized test surfaces and respect project resource limits. No device
  or build access means a clear open acceptance item, not fabricated completion.

## Native handoff and evaluation

For a reference-to-build handoff, read
[Native handoff](references/native-handoff.md). Use it to turn an approved
concept into a bounded comparison, not to require a new preview for a copy edit.
When evaluating this skill, test observable decisions with realistic supplied
artifacts; a valid manifest or familiar wording is not behavioral proof.

## Completion standard

Judge the result by task clarity, visual coherence, native interaction, accessible
adaptation, product character and honest state communication. State the remaining
concrete defects rather than assigning an unsupported "premium" score. Summarize
what changed, what was actually seen/tested, and the next meaningful visual gap.
