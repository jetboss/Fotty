# Fotty QA Playbook

Last updated: 2026-05-07

## How To Use This With NotebookLM

Upload this file with `Fotty-Project-Memory.md`. After each test session, add:

- device
- build time
- match tested
- provider tested
- expected behavior
- actual behavior
- screenshots
- logs, redacted

Then ask NotebookLM:

“Compare this test note to the QA playbook. What failed, what should be retested, and what is the likely subsystem?”

## Device Test Script

### 1. Basic Launch

- Install latest build on iPhone 15 Pro Max.
- Launch Fotty.
- Confirm app opens without crash.
- Confirm Live tab loads.
- Confirm match cards are usable and not visually broken.

Expected:

- no frozen launch
- no blank main screens
- no major scaling issue

### 2. Regular Provider Playback

- Open a match with known non-P2P provider streams.
- Confirm the player opens.
- Confirm the selected stream autostarts without tapping play.
- Confirm the player controls auto-hide.
- Confirm pause/play works.
- Confirm close works.

Expected:

- playback starts automatically
- no repeated pause every few seconds
- no source selector modal appears unexpectedly

### 3. Broadcast Source Switching

- While in portrait player mode, scroll below the video.
- Find “Available Broadcast Sources.”
- Select another regular provider source.
- Expand “P2P Channel Catalog.”
- Select a P2P source.

Expected:

- all stream changes are made from the broadcast section
- no old source-selection sheet appears
- selected source clearly becomes active
- P2P selection shows warmup/prepare progress when needed

### 4. P2P Warm Source Reuse

- Pick a P2P source that recently played.
- Close the player.
- Reopen the same match/source shortly after.

Expected:

- broker does not create a fresh cold session if a reusable session exists
- startup is faster than first cold attempt
- no stale manifest or 401/403 segment issue

### 5. Cold P2P Source

- Pick a P2P source not recently used.
- Watch the warmup UI.
- Wait through the prepare window.

Expected:

- progress text changes as broker state changes
- UI does not look stuck
- if source fails, it fails calmly and lets user pick another broadcast

### 6. Web Embed Behavior

- Pick a source that opens through web embed.
- Confirm video tries to start automatically.
- Confirm ad/popup blockers do not navigate away from the player.
- Confirm controls and close button remain usable.

Expected:

- playback starts or clearly fails
- no ad redirects taking over top-level navigation
- no endless silent loading

### 7. PiP

- Start native playback.
- Swipe up to leave the app.

Expected:

- iOS starts Picture in Picture where supported
- playback continues
- returning to app resumes cleanly

### 8. Live Activity / Dynamic Island

- Start a stream for a live match.
- Lock screen or leave app.

Expected:

- Live Activity shows match/source/phase where supported
- state updates from loading to playing/failure
- no sensitive provider URL is shown

### 9. Failure UX

Force or observe a source failure.

Expected:

- user sees calm message
- no raw URLs, tokens, stack traces, or proxy internals
- button sends user back to broadcast sources, not to an unexpected modal

### 10. Match Context QA

Open match hub/timeline/arena/poll for live matches in different sports.

Expected:

- poll names match the actual teams/sport or are hidden/generic in a truthful way
- football timeline does not appear for tennis/basketball if data is not valid
- placeholder content is not presented as real data

## Bug Report Template

Use this template after every failed test:

```text
Date/time:
Device:
Build source:
Match:
Sport/league:
Source selected:
Provider type: regular / web embed / P2P
Expected:
Actual:
Screenshot/video:
Approx time waited:
Did controls respond:
Did close respond:
Did another source work:
Relevant logs, redacted:
Likely subsystem:
```

## Subsystem Clues

If the video never opens:

- likely match-to-provider mapping or stream resolver

If player opens but does not start:

- likely AVPlayer handoff, autoplay, headers, or web embed page behavior

If P2P says preparing forever:

- likely broker session state, engine warmup, stale session, or server capacity

If P2P starts then black screen:

- likely manifest/segment reachability, codec incompatibility, or proxy rewrite issue

If stream pauses every few seconds:

- likely buffering, segment health, player wait behavior, network, or provider throttling

If wrong names appear in poll/timeline:

- likely placeholder data, wrong match mapping, or sport-scoping issue

If PiP does not start:

- likely AVPlayerLayer PiP availability, stream type, scene phase timing, or user/device setting

