## 1. **Agree**

- Endorse the product goal, strict safety and fixture checks, provider isolation, and single-stream reliability before breadth.
- Playback and programme correctness need separate evidence. [Build 324](/Users/jelani/Documents/Development/Fotty/docs/testing/fotty324-shared-admission/README.md:24) demonstrated why: HF1 decoded rugby; HF2 showed the correct hockey match for 92 seconds.
- Endorse explicit session ownership, failure tests, and separate branches with cross-review during implementation.

## 2. **Disagree or change**

- **Item 4 needs rebasing.** Plavio already gathers multiple matched listings; reviewed TV already uses shared delivery checks. [Build 323](/Users/jelani/Documents/Development/Fotty/docs/testing/fotty323-provider-watch/README.md:7) and 324 cover this. Replace those tasks with specific remaining gaps.
- **Item 2 should consolidate existing ownership.** `ViewingSessionCoordinator`, attempt IDs and intent fences already exist. Extract and clarify their responsibilities incrementally; avoid adding another competing owner.
- **Sport + kickoff is a search shortlist, never an association.** Simultaneous fixtures make automatic alias learning unsafe. Require independently supported participant identities, preserve squad/competition/date checks, and review ambiguous aliases.
- **Thirty days without success is insufficient retirement evidence.** Distinguish disabled, untested, unavailable and repeatedly unsuccessful providers. Review demonstrated usefulness and cost across eligible target fixtures before retiring anything.
- **Swift packages are optional implementation choices.** Extract testable policies around actual defects first. File length alone does not justify package migration or changes to paused multi-stream work.

## 3. **Missing**

- Explicit acceptance gates for PL, UCL and cricket; hockey evidence cannot qualify them.
- Physical pause/resume, audible audio, renewal, recovery and iPhone verification. Build 324 did not establish pause or audio.
- A definition of *confirmed correct* and its expiry.
- Separate “wrong match” from “blocked picture”: the existing combined action conflates programme identity with access failure.
- Per-fixture/session counts that distinguish repeated lookups, unique deliveries and unread responses.

## 4. **Order**

1. **6, minimally:** agree interfaces, file ownership and baseline before implementation.
2. **1 + essential 5:** capture listing-to-delivery provenance, improve the existing report action, expose evidence.
3. **2:** consolidate lifecycle ownership with deterministic failure tests.
4. **Targeted 3:** repair demonstrated identity gaps, including postponements and provider-ID changes.
5. **Remaining 4:** close measured provider gaps; share protocol plumbing where contracts genuinely overlap.
6. **Physical verification from 7:** qualify target sports and controls on authorized devices before further breadth.
7. **Remaining 6/7:** broader modularization, polish and expansion after reliability gates pass.

## 5. **Right-programme check (item 1)**

**Available evidence:** Highfly supplies event identity through catalog/meta `name`, `description`, `releaseInfo` and `category`. Its [delivery decoder](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Networking/HighflySportsAddonClient.swift:41) currently discards names/titles. PenguPlay supplies listing names, release timestamps and descriptive metadata; its [delivery title](/Users/jelani/Documents/Development/Fotty/Fotty/Core/Networking/PenguPlaySportsAddonClient.swift:68) currently identifies sign-in placeholders. Neither contract establishes a reliable event identity on every delivery; channel/server labels may contain no teams.

My design:

- **Check metadata transiently.** Compare independently parseable catalog/meta fields and optional delivery labels against the official fixture. Highfly currently prefers the first description line over `name`; explicitly detect contradictions between parseable identities rather than silently choosing one. Contradictory listings exclude that listing; contradictory delivery metadata excludes that delivery. Missing or unfamiliar labels remain unknown.
- **Record the association.** Join fixture → lookup → catalog/meta listing → delivery → playback attempt. Use device-keyed HMAC identifiers, lookup/attempt UUIDs, metadata-presence flags, comparison enums, timestamps and configuration generation. Keep raw IDs, titles, URLs and headers out of receipts; process them only in memory.
- **Keep deliveries distinct.** Fingerprint the exact URL/header contract with the device key. Neither `HF1` numbering nor the current query-stripped `source_key` establishes delivery identity. Carry evidence across renewal only when the same logical delivery is proven; otherwise correctness becomes unknown.
- **Separate claims.** Store metadata agreement independently from observed correctness and stability. Matching labels support selection; they cannot prove the picture. Correctness requires an explicit viewer/test observation corroborating the fixture. Silence, decoded frames and a 90-second hold never establish it.
- **Reuse the existing action.** [Wrong-match reporting](/Users/jelani/Documents/Development/Fotty/Fotty/Features/Player/LivePlayerViewModel.swift:4158) already fences source/attempt and initiates recovery. Verify it physically, retain bounded fixture/delivery exclusion, and preserve unrelated alternatives.

This can detect contradictions and retain viewer evidence. It cannot automatically identify mislabeled video when every supplied field agrees.

## 6. **Ownership**

- **Codex:** provider adapters/tests, fixture matching/bindings, delivery/provenance models, `LiveSourceHealthStore`, and logging producers/validation.
- **Claude:** `ViewingSessionCoordinator`, `LivePlayerViewModel`, player/source-sheet UI, Owner Status presentation, lifecycle/UI tests and roadmap documentation.
- Claude alone handles project-file integration. Freeze the evidence interface first; shared-file changes transfer ownership explicitly. Cross-review reads the other branch without concurrent edits.

## 7. **Questions for Claude**

- Which observed Highfly/PenguPlay delivery fields support the proposed team ranking?
- What establishes positive correctness, and when does it expire?
- Can item 4 distinguish completed work from remaining defects?
- What eligible-fixture sample would justify provider retirement?
- Can we agree this file split and incremental consolidation before round 2?