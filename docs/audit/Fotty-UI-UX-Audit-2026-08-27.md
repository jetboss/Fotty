# Fotty UI and UX audit

Date: 27 August 2026  
Baseline: current local `2.0.0 (33)` source, including the unreleased beta-usability patch  
Scope: presentation, navigation, interaction clarity and perceived quality. Recommendations only; no app changes.

## Verdict

**A credible closed-beta interface, but not yet a premium daily-use experience. My subjective overall rating is about 6/10.** This is a design judgment, not a measured satisfaction or retention score.

Fotty has a recognizable black-and-amber identity, sensible top-level destinations, a familiar squad pitch, and useful connections between football and FPL. It is not an incoherent prototype. However, small text, competing panels, technical language, ambiguous labels and inconsistent interaction details make it feel more like a capable enthusiast tool than a finished consumer product.

Would the UI encourage use? The watch/FPL combination gives people a reason to try it. The interface does not yet make the value effortless to discover or follow. Experienced FPL users will tolerate more of its density than newcomers. Whether it improves repeat use requires actual tester observation; screenshots cannot establish that.

The right direction is **refinement with selective screen recomposition**, not replacing the brand, adding more tools, restoring duplicate feeds, or redesigning everything from scratch.

## Evidence and limits

The installed `/Applications/Fotty.app` was visibly outdated and was excluded from the verdict. One temporary current-source Mac Catalyst Debug build was used instead.

| Coverage | Evidence obtained |
| --- | --- |
| Home | Initial empty/recovery presentation and loaded catalog, hero, filters, rows and tab navigation |
| My Matchday | FPL-relevant fixtures, reason labels and kickoff-clash banner |
| FPL | Plan, Squad, Coach without sending a request, Tools, Transfer Lab, Captain, pre-deadline Live Points |
| Settings/support | Main settings, notification explanation, Help, empty feedback form |
| Responsive composition | Narrow and expanded Catalyst windows; compact iPhone branches inspected in source |
| Other FPL tools | Source review of Price Radar, Wildcard, Compare, multi-gameweek planning, Fixture Difficulty, Mini-leagues, Rival Race and Decision Journal |
| Other states/surfaces | Source review of onboarding, manager connection, Match Center, player/recovery/source picker, MultiView, widgets and Live Activities |

This was **not** fresh iPhone/iPad visual certification, a provider-playback test, a complete VoiceOver run, a live-gameweek observation, or a new-user study. Catalyst screenshots do not prove iPhone keyboard, safe-area or touch behavior. The web companion and App Store marketing pages are not covered.

Two accessibility-inspection attempts around navigation toward Price Radar stalled. A short process sample placed the main thread in accessibility hierarchy enumeration. This does not isolate the trigger to Price Radar or prove that ordinary phone use freezes. No Price Radar screenshot is claimed. The temporary process was stopped; no fix was attempted.

Existing automated accessibility and hardware acceptance remain useful historical evidence. They do not certify subjective visual polish or every production-data state.

## What should stay

- **Black and amber:** recognizable, restrained and appropriate for football viewing. No wholesale palette replacement is needed.
- **Four main destinations:** Home discovers; Matchday personalizes; FPL helps decisions; Settings manages the app. The distinction is now defensible.
- **The football pitch and shirts:** the most immediately recognizable football-specific surface. Improve readability without discarding this mental model.
- **Plan / Live / Review:** orienting the first FPL workspace around the gameweek is useful.
- **Numbered sources and in-app recovery:** a cleaner direction than provider-health jargon, browser escape buttons or unsupported playback promises.
- **Optional setup and explicit FPL confirmation:** good newcomer safeguards. Keep watching independent of setup.
- **Truthful estimates, privacy and local-draft boundaries:** preserve them, but present them in clearer language and closer to the relevant decision.

## Priority findings

P1 means address before a broader tester rollout. P2 means important polish and usability work. P3 means later refinement or a verification gap, not a demonstrated release blocker.

### UI-01 · P1 · Important information is too small

**Observed + source-confirmed.** FPL labels, pitch nameplates, fixture strips and metric captions are visibly dense. The compact Squad implementation explicitly uses 8-point player names, 7-point opponents/lenses and a name shrink factor of 0.7. Command Center has fixed 8–9-point captions. This is not merely a screenshot scaling issue: these are fixed source sizes. In contrast, `fottyScaled` is a semantic-style helper, so its numeric argument must not be mistaken for an exact point size.

Apple recommends 17-point default and 11-point minimum custom text on iOS/iPadOS; essential information should be comfortably readable, not just technically fit. [Apple typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography?changes=_5)

**Recommendation:** make player identity and the selected decision metric readable first. Reduce redundant price/fixture/metadata layers before shrinking text. At accessibility sizes, reflow into readable rows instead of forcing five tiny labels across the pitch. Do not enlarge the entire app indiscriminately or undo the previous iPhone overflow fix.

Evidence: [Squad nameplates](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLSquadPitchView.swift:716), [Command Center metrics](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLCommandCenterView.swift:109), [FPL header stats](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/FPLMainView.swift:502).

### UI-02 · P1 · Labels sometimes promise more than the visible evidence supports

**Observed:** Home and Matchday displayed `Watch` on tomorrow's fixtures. The ability to open a provider listing is legitimate; the label does not explain that the match has not started. Preserve the manual opening capability, but use `Open broadcast` outside the live window and `Watch live` when appropriate. Do not remove access to a source merely because the fixture is future-dated.

**Observed:** the FPL header said `Gameweek 2` and `GW POINTS 95`, while a separate lower strip said the picks were from GW1 and the confirmed review was GW1. This audit does not dispute the number. It disputes the missing gameweek beside the number. Use an explicit label such as `GW1 confirmed points`, separate from the GW2 plan.

**Source-only:** Match Center says `Lineups not announced` whenever lineups are absent near kickoff or during play. Missing feed data does not establish that teams have not announced them. Use `Lineups not available in Fotty yet` unless an announcement state is known.

Evidence: [row action](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/LiveEventCard.swift:78), [hero action](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/HeroMatchCarousel.swift:173), [points header](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/FPLMainView.swift:478), [lineup state](/Users/jelani/Documents/Development/Fotty/Fotty/Features/MatchHub/Tabs/InsightsHubTab.swift:94).

### UI-03 · P1 · Moving between football and FPL loses your place

**Observed + source-confirmed.** After visiting FPL tools, moving to Settings and returning to FPL, the screen loaded again and returned to Plan. The root swaps entire destination views; the FPL workspace and selected tool are local view state initialized to the gameweek workspace.

That interrupts the app's main promise: checking football while working on an FPL decision. This finding is about navigation context, not a claim that saved drafts were deleted.

**Recommendation:** preserve each destination's current screen, scroll position and in-progress UI context across ordinary tab changes. Refresh content without replacing an already useful screen with a full-screen spinner. Keep manager/season isolation intact.

Evidence: [root destination switch](/Users/jelani/Documents/Development/Fotty/Fotty/App/MainTabView.swift:65), [FPL local workspace state](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/FPLMainView.swift:3).

### UI-04 · P1 · Some colors undermine readability and meaning

The base theme is not the contrast problem. Using the source sRGB colors and standard relative-luminance calculation:

| Pair | Approximate contrast |
| --- | ---: |
| Black text on theme amber | 9.97:1 |
| Theme tertiary text composited over theme surface | 7.80:1 |
| White text on Squad's easy-fixture green | 3.19:1 |
| White text on Squad's hard-fixture red | 4.34:1 |
| White text on Fixture Difficulty's level-4 red | 3.96:1 |

The last three are below the 4.5:1 normal-text benchmark, particularly concerning with 7–10-point text. These are source-color calculations, not a claim to have measured every rendered state or completed an accessibility certification. [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)

Fixture difficulty also uses grey for level 3 on the pitch but yellow in the table. Individual table cells show opponent/location but not the difficulty value; the color carries that information. A numbered legend alone does not make every cell understandable without color. [W3C use-of-color guidance](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)

**Recommendation:** share one difficulty palette, use verified text contrast, and expose difficulty through a number or accessible textual description. Keep amber for selection/actions, with a consistent treatment of warnings. Do not brighten every secondary label; the core text tokens already have healthy contrast.

Evidence: [pitch fixture colors](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLSquadPitchView.swift:766), [fixture table](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLFixtureTrackerView.swift:12), [theme](/Users/jelani/Documents/Development/Fotty/Fotty/Design/Theme.swift).

### UI-05 · P2 · Home sacrifices recognition for density

**Observed:** `Internacional de Bogotá` became `I. de`; `Coventry City` became `C. City`; the hero shortened `Estudiantes de La Plata` to `Estudiantes de`. This loses identity despite available horizontal room. Several fixtures also appeared twice with naming variants, such as Alaves / Deportivo Alavés. The duplicate rows are a visible trust problem; their upstream cause was not diagnosed in this UI-only audit.

**Recommendation:** preserve recognizable club names. Use curated common abbreviations, otherwise allow a second line or a sensible truncation that retains the distinctive name. Never cut a name down to a connector. Show real competition identity when supplied; do not invent missing league information. Resolve visible duplicate fixtures through a separately scoped identity check before treating the list as polished.

Home's lead card is a reasonable foundation, but generic `FOOTBALL` labeling and inconsistent crest availability make parts of it feel like a raw feed. Improve editorial hierarchy and fallback-badge consistency rather than adding decorative cards, unrelated news, or another carousel.

Evidence: [name formatting](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/MatchCardFormatting.swift:42), [row rendering](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/LiveEventCard.swift:141).

### UI-06 · P2 · FPL needs a stronger decision hierarchy

**Observed.** The manager header, workspace bar, phase panel, three metrics, three action cards, freshness strip, reminder and previous review all compete on Plan. The useful next action is there, but so is a considerable amount of equally styled supporting material. Tools then presents eleven similarly weighted tiles.

**Recommendation:** lead with the current gameweek and the most important decision, follow with two or three supporting facts, and keep secondary evidence available below. Group existing tools by intent—plan, follow the gameweek, review—without creating more navigation layers or removing advanced capabilities. Live-only destinations should explain their timing before users open them.

My Matchday repeats FPL involvement above and inside each card. Keep one useful reason, not two copies. Change `start 0 minutes apart` to `Both start at 10:00 AM`, using the actual relevant date/time. Group later fixtures by day so the screen feels like a plan rather than a smaller feed.

Evidence: [Plan composition](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLCommandCenterView.swift:14), [Tools grid](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/FPLMainView.swift:317), [Matchday reason wrapper](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Social/ArenaDiscoveryView.swift:232).

### UI-07 · P2 · The language often describes the implementation, not the user's task

Observed examples include `Current Fotty squad passes structural checks`, `event-live`, `EST. FT`, the bare Coach control `5 GW`, and Captain's `ep_next` explanation. Source review adds `price_change_projections`, `CONSTRAINED HEURISTIC`, and `5-AXIS NORMALIZED FOTTY PROFILE`.

**Recommendation:** use language such as `Squad meets FPL rules`, `Estimated free transfers`, `Plan ahead: 5 gameweeks`, and `FPL next-gameweek estimate`. Move algorithm/field names into optional methodology details. Keep uncertainty and local-only consequences visible beside the decision; do not bury safety caveats in Help.

The Captain screen also displayed a recommended player with a lower visible points estimate than the next-ranked players. This does not prove the ranking is incorrect, but the UI does not explain why rank and estimate differ. State the decisive reason and distinguish the ranking score from the displayed points estimate.

Evidence: [Captain](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLCaptainPickerView.swift:61), [Coach controls](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLAICoachView.swift:176), [Price Radar](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLPriceAlertsView.swift:42), [Wildcard](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLWildcardGeneratorView.swift:52).

### UI-08 · P2 · Navigation and control styling are not fully consistent

**Observed:** Captain opens below `All tools` without a visible Captain page title. Other tools introduce their own differently styled headings. Home menu pickers and the FPL loading recovery action rendered system blue while most app actions use amber. FPL's internal workspace controls also lack the explicit selected accessibility trait used by the main tabs.

**Source-confirmed touch risk:** row bookmarks are 32×32 points; row Watch buttons have a 32-point minimum height; several player controls are 40 points. A compact visual button need not have a compact hit region. This is a source-size concern, not a new physical hit-test failure. Apple's general target guidance is at least 44×44 points. [Apple UI design tips](https://developer.apple.com/design/tips/)

**Recommendation:** one consistent tool title/back pattern, one action hierarchy, one tint policy, and reliable selected/disabled states. Retain compact-looking stream targets while expanding their invisible touch area without overlap. Do not add a second unmute button or another overlay over provider controls.

Evidence: [tool destination wrapper](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/FPLMainView.swift:317), [workspace buttons](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/FPLMainView.swift:254), [Home pickers](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Dashboard/Components/SportsCategoryBar.swift:29), [player controls](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/Components/PlaybackControlsOverlay.swift:20).

### UI-09 · P2 · Settings and feedback are clearer functionally than visually

**Observed.** Settings begins with `Guest`, `LOCAL`, `@fan` and Edit Profile, even though FPL has a connected team. These are different identities, but the UI makes the user reconcile them. Notifications occupies a large explanatory block before the actual toggles. Help is readable but is one long article. The feedback form's two prompts are faint placeholders rather than persistent visible field labels; Copy/Share look less obviously disabled than their accessibility state indicates.

**Recommendation:** prioritize teams, FPL connection, playback and support over the local profile card. Explain local identity plainly if it stays. Separate `While using Fotty` from `FPL deadline reminders`, retaining honest limits with shorter summaries and expandable detail. Add persistent visible feedback-field labels, clear required-field guidance and an unmistakable disabled state. Do not present report preparation as successful delivery.

The new native support flows are worth keeping. Their existence fixes dead ends; this pass should make them easier to scan.

Evidence: [Settings](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/SettingsScreen.swift:39), [feedback form](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Settings/Views/SettingsSupportViews.swift:128).

### UI-10 · P2/P3 · Finish the experience between the main screens

- **Empty states:** pre-deadline Live Points tells people to use Command Center but offers no direct Plan action. Rival Race's source tells users to load Mini-leagues and then return; provide that navigation directly. Home briefly showed `No events right now` before the catalog populated; loading and genuinely empty should not look the same.
- **Wide layouts:** the expanded FPL workspace remains a centered single column. The readable width cap is good, but some decision/evidence relationships could use a deliberate two-column composition on sufficiently wide screens. Do not revive the previously rejected Home side rail just to fill space.
- **Motion:** the shared LivePulse repeats without an explicit Reduce Motion branch. Verify motion preferences and provide a static equivalent. This is source evidence, not a full motion-sensitivity audit.
- **Appearance:** dark-only is coherent for viewing, but daylight legibility on an actual phone remains unverified. Do not promise a new light theme before testing whether contrast and hierarchy solve the problem.
- **System surfaces:** the deadline widget has a clear job and direct FPL route. Live Activity copy such as `native playback` is unnecessarily technical. Recheck small widgets, long team names and tinted appearances on hardware before changing their design.

Evidence: [Live Points](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLLiveTrackerView.swift:209), [Rival Race empty state](/Users/jelani/Documents/Development/Fotty/Fotty/Features/FPL/Views/Components/FPLRivalMatrixView.swift:113), [LivePulse](/Users/jelani/Documents/Development/Fotty/Fotty/Design/Components.swift:538), [Live Activity](/Users/jelani/Documents/Development/Fotty/FottyLiveActivityExtension/FottyLiveActivityWidget.swift:174).

## Deeper-screen review

These are presentation recommendations, not requests to alter FPL calculations or provider behavior.

| Surface | Assessment and next UI improvement |
| --- | --- |
| Transfer Lab — visual + source | Comparing roll/one/two moves is useful. Reduce nested panels; put horizon, modeled-gain status and local-draft consequence beside the main figures/action. |
| Captain — visual + source | Readable shortlist structure, but missing page title, tiny rationale and unexplained rank/points relationship. |
| Live Points — pre-deadline visual, live state source | Before/after-autosub structure is promising. Keep official versus provisional gameweek context adjacent to totals; give the waiting state a direct Plan route. Active-gameweek rendering was not observed. |
| Price Radar — source | Direction and uncertainty are represented. Replace raw field names, explain what a percentage means, and verify the long-list accessibility behavior on real hardware. |
| Wildcard — source | Draft consequence and legal validation are explicit. Rename implementation badges; make lock/exclude language approachable and prioritize the proposed squad over setup controls. |
| Compare — source | Two-player evidence is useful. Long player menus need searchable selection; prioritize comparable values and explain units before the radar profile. |
| Multi-gameweek planner — source | Shared horizon and saved scenarios support real planning. Make the selected week, modeled horizon and draft status the leading labels; simplify technical copy. |
| Fixture Difficulty — source | Compact matrix is familiar. Improve text size/contrast, use one difficulty key, retain team context while scrolling, and make horizontal continuation discoverable. |
| Mini-leagues — source | Table, own-team emphasis and pagination are sensible. Explain that another manager row opens rival context; preserve league/page when moving around the app. |
| Rival Race — source | Clear purpose once available. Give pre-deadline and no-league states a direct useful destination instead of instructions to navigate elsewhere. |
| Decision Journal — source | The empty-state action and manager/season scope are good. A clear status plus concise rationale should lead; keep reflection detail secondary. |
| Match Center — source | One scoreboard/overview and FPL lens are the right structure. Fix unknown-lineup wording and small labels; validate actual long-name layouts before declaring polish. |
| Player/source picker — source | Keep video dominant, auto-hiding controls, capability-gated PiP and explicit retry. Audit touch regions and dismiss labels; retain one provider-owned unmute interaction. No new playback success is claimed. |
| MultiView — source | Secondary, gated feature. Audio-focus and swap icons need immediate meaning and proper touch regions; do not add permanent overlay clutter. |
| First-use/manager connection — source | Optional setup, explicit team confirmation and recovery routes are sound. Use the same typography/action system as the main app and keep permission requests contextual. |

## Recommended order if implementation is approved

1. **Readability and trust:** UI-01 through UI-04; recognizable names; touch regions; persistent field labels. Preserve existing playback and data contracts.
2. **Coherence:** stable tool titles, plain-language copy, preserved navigation context, consistent actions/colors and helpful empty states.
3. **Character and composition:** refine Home's lead, simplify Plan, group Tools, remove duplicate labels, then validate wider FPL layouts. Keep the approved icon and football identity.

No new feature is required to make this release feel substantially better.

## How to verify the next design pass

Use the actual supported iPhone and iPad, with no simulators on this workstation. Check normal and large Dynamic Type, iPhone Display Zoom, portrait/landscape, Coach keyboard appearance, daylight, Reduce Motion, and a short VoiceOver journey. Verify normal, loading, empty, offline/stale and provider-error states; use deterministic fixtures for states that cannot safely be produced live.

Give a small first group of testers these tasks without coaching:

1. Find a match starting tomorrow and explain what its primary button will do.
2. Save it and find it again in Matchday.
3. Find their confirmed points and identify the gameweek and whether the total is provisional.
4. Open an FPL planning tool, inspect a match, then return to the same place.
5. Prepare a problem report and explain whether it has actually been sent.

Record hesitation, wrong taps, misunderstood labels and any need to explain the interface. The success criterion is understandable, continuous journeys—not simply passing a compile or adding more controls. Do not claim engagement uplift without tester evidence.

## Work performed and cleanup

- No app source, design, version, provider configuration or FPL draft was edited by this audit.
- No Coach request, feedback submission, device installation, archive, upload or Git publication was performed.
- One temporary current-source Catalyst build succeeded. No simulators or parallel builds were used.
- The 329 MB temporary build and sample were deleted; generated audit captures were removed or had already been removed by the inspection service. Approximately 42 GiB remained free afterward.
- This report and its durable-memory summary are the only intentional authored changes; the standard memory-finishing script regenerates the local reference bundle.

**Bottom line:** good enough to continue a small closed beta, average-to-good visually, not yet premium. Improve readability, truthful labeling and continuity first; then make the existing capabilities feel like one product.
