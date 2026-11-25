# Fotty 2.0.0 (101) — private app-wide UI iPad candidate

Installed 2026-09-19. Status: **private Jet iPad acceptance candidate**.
The owner authorized a cable install and device check on Jet iPad after the
app-wide Apple-aligned UI source pass. No TestFlight upload, iPhone install,
tester change, backend deployment, commit or Git publication is authorized.

## Included work

- Complete the presentation pass across Home, Search, Matchday, FPL workspaces,
  Settings/onboarding, Match Hub/insights and source/recovery surfaces.
- Preserve the four-tab architecture, sports artwork, badges, compact Watch
  actions, existing data projections and playback ownership.
- Improve adaptive labels and actions, visible press/selection/disabled states,
  contrast accommodations, large-text reflow, Coach keyboard avoidance and
  active-source retry consistency.
- Retain full useful iPad width and adaptive two-column compositions rather than
  introducing fixed phone-width content or side gutters.

The detailed implementation and limitations are in
`docs/audit/Fotty-Appwide-UI-Completion-2026-09-19.md`. This private gate changes
the app and extension build number from 100 to 101; it does not add another
runtime feature after the completed source gate.

## Build and installation evidence

- Official Xcode 27 (27A266a) is explicitly pinned. No simulator is selected or
  booted. One bounded temporary DerivedData root is reused sequentially.
- The preceding full Catalyst gate passes **586 tests, zero failures and two
  intentional opt-in skips**. Generic unsigned iOS Release compilation passes.
- A signed optimized Release builds for the connected Jet iPad (iPad Air 4,
  iPadOS 27.0). App and Live Activity extension both report 2.0.0 (101), the app
  is arm64-only, strict nested signature verification passes and the embedded
  profile contains the exact device UDID.
- CoreDevice installs build 101 in place over the prior private build without
  removing the app container. CoreDevice independently reports
  `com.jelani.Fotty`, version 2.0.0, bundle version 101.
- The app stays present for the full 60-second launch hold. Fresh device queries
  before and after the visual journey find **zero Fotty crash-log files**.

## Physical presentation evidence

Current build 101 screenshots were captured from the physical iPad at
2360 × 1640 and inspected at original resolution:

- **Home**: fills the landscape canvas with no black side bars; the sports grid,
  badges, two-column schedule cards, adjacent reminder actions and centered dock
  remain readable and aligned.
- **Matchday**: uses a balanced two-column fixture grid, retains team badges and
  countdown/reminder hierarchy, and keeps navigation and Browse reachable.
- **FPL onboarding**: uses an intentional wide split between explanation and
  manager-link entry, with no clipping or keyboard-safe-area regression visible
  in the disconnected state.
- **Settings**: groups Preferences, Playback, Your data and Support & About into
  a coherent wide layout. Appearance, interests, notifications and version
  `v2.0.0 (101)` are immediately legible without diagnostic copy.

### Connected FPL persistence acceptance

After the owner connected the team, a private preference inspection confirmed a
valid nonzero manager ID and current-season manager confirmation are stored in
the app container. The ID itself is intentionally omitted from this record.
Fotty was then fully terminated and relaunched through its FPL route. The current
connected Live workspace loaded directly with official FPL data; the manager
entry screen did not return. A fresh crash-log query still returned zero Fotty
files. No preference was rewritten for this verification and no source build was
required. Fotty is intentionally left on the connected FPL workspace.

The developer device viewer is display-only on this host. For exact-screen
inspection without installing a UI-test helper, Matchday used Fotty's own
deep-link route and the selected-tab preference alone was changed while Fotty
was stopped to reveal Settings. The complete preference file was preserved; only
`fotty.selectedTab` changed, and it was restored to `Home` afterward. The final
physical screenshot confirms Home selected. No manager ID, appearance, interests,
notifications, source choices or other user data were changed.

## Honest remaining acceptance

This closes installation, launch stability and wide landscape presentation for
the four primary tabs on Jet iPad. It does **not** qualify:

- Search, Match Hub and player/source interactions on this exact physical build;
- light/System appearance, accessibility text, narrow iPad window or portrait;
- Coach multiline keyboard/draft preservation or accessible squad swap behavior;
- stream decoding, playback controls, source switching, PiP or background soak;
- iPhone behavior, another iPad model, TestFlight installation or owner visual
  acceptance of every screen.

Those remain targeted interaction checks, not reasons to mislabel the verified
build as unstable. Existing playback and data ownership were not changed by this
UI batch.

## Cleanup

All task-owned DerivedData, temporary preference copies and screenshots are
deleted after this record is updated. No user cache, app data, retained release
receipt or unrelated project output is removed. Fotty remains installed and is
left open on the connected FPL workspace. The bounded gate occupied 308 MiB
before deletion; the Data volume reports 62 GiB available afterward. The
temporary Device Hub viewers are also closed. The source tree is not committed,
pushed or distributed.
