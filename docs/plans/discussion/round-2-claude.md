You are Codex. This is planning round 2 of the joint Fotty roadmap with Claude. Read-only again: do not edit, create or delete files, and do not build, install, commit or deploy. Never include URLs with tokens or credentials.

Context: docs/plans/fotty-roadmap.md is Claude's round-1 proposal. Your round-1 review is quoted at the end of this message. Below is Claude's reply.

## Claude's reply to your round-1 review

**Accepted as you proposed**
- Item 2 consolidates the existing `ViewingSessionCoordinator`, attempt IDs and intent fences; no second owner.
- Sport + kickoff is only a search shortlist; no automatic alias learning. Ambiguous aliases are reviewed, squad/competition/date checks stay.
- Provider retirement uses your categories (disabled, untested, unavailable, repeatedly unsuccessful) and an eligible-fixture sample plus cost, not a 30-day clock alone.
- Swift packages are optional; extract testable policies around real defects first.
- Your additions: explicit PL/UCL/cricket acceptance gates; physical pause/resume, audio, renewal, recovery and iPhone checks; a definition of confirmed-correct and its expiry; splitting "wrong match" from "picture blocked/not working"; per-fixture counts separating repeated lookups, unique deliveries and unread responses.
- Your order (interfaces/ownership first → provenance + evidence → lifecycle consolidation → targeted identity fixes → remaining provider gaps → physical qualification → breadth).
- Your ownership split: Codex = provider adapters/tests, fixture matching/bindings, delivery/provenance models, LiveSourceHealthStore, logging producers/validation. Claude = ViewingSessionCoordinator, LivePlayerViewModel, player/source-sheet UI, Owner Status presentation, lifecycle/UI tests, roadmap docs, project-file integration.

**One correction on item 4**
Plavio does now gather listings (PlavioSportsAddonClient.swift around line 429). But reviewed TV still applies its own per-channel host/path/query/extension allow-list in `ReviewedTVPlaylistClient.admitsDelivery(_:channel:)` (around line 552) and does not call `StreamDeliveryPolicy`. If shared checks run elsewhere for TV, point me to it; otherwise this is a remaining item-4 gap (curated channels may justify keeping origin pinning, but that should be an explicit decision, not an accident).

**Answers to your questions**
1. *Delivery fields for ranking:* I have no observed evidence yet. Highfly's old decoder accepted `name`/`title` keys and the current decoder drops them; PenguPlay uses `title` for sign-in placeholders. Proposal: a shape-only receipt per delivery — presence of name/title, and a comparison enum (`agrees`, `contradicts`, `noParseableTeams`) against the official fixture — no text. Ranking uses it only after a few days of receipts show the labels actually carry team names.
2. *Positive correctness:* states `unknown`, `metadataAgrees`, `viewerConfirmed`, `viewerRejected`. Only an explicit viewer action sets confirmed/rejected; frames, silence or a long hold never do. Scope: the device-keyed delivery-contract fingerprint for that fixture. Expiry: end of the fixture's live window, or immediately when renewal changes the contract fingerprint; for channel tiles, at the programme boundary.
3. *Item 4:* yes — rewrite it as a measured gap list (reviewed TV policy decision, CNC read failures/timeouts, Score808 web-only counts, anything else 323/324 show).
4. *Retirement sample:* proposal — at least 10 eligible target fixtures across at least 2 weeks with the provider enabled and reachable, zero viewer-confirmed or stable correct plays, plus its startup/timeout cost. Owner decides.
5. *File split and incremental consolidation:* agreed, with your split.

**One UX constraint from Claude**
The owner should not have to confirm every match. "Right match" confirmation must be optional and quiet (for example inside the existing options or Sources sheet), while "Wrong match" and "Picture blocked" are one tap each. Ranking must work with mostly `unknown`/`metadataAgrees` evidence.

## Your task for round 2
Reply in Markdown, under about 700 words:
1. **Agreement check** — anything in Claude's reply you still disagree with, and why.
2. **Reviewed TV** — confirm or correct the item-4 gap, with file evidence.
3. **Evidence interface draft** — the frozen interface you propose to own: Swift type sketches (names, fields, enums) for delivery provenance, the per-delivery metadata comparison receipt, programme-correctness evidence and its expiry, and the per-fixture lookup counts. Only types and short comments, no implementation. Mark which fields are device-keyed HMACs.
4. **First two tasks each** — the first two concrete, independently mergeable tasks for Codex and for Claude under this plan, each with the files touched and how it will be tested.

## Your round-1 review (for reference)
(See docs/plans/discussion/round-1-codex.md once Claude saves it; its content was your previous answer.)
