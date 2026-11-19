# Fotty Sports Hub

Fotty 3.0 is an iOS-first live sports companion: match-day discovery across
sports, a Sports TV guide, personal Matchday planning and optional third-party
playback of one match at a time.

Retired in 3.0: the FPL workspace was removed in build 332. Only public scores
and the legacy backup types needed to read older saved data remain. Two-match
viewing (Watch Two) was removed on 19 November 2026; a future version would be
rebuilt on the simplified single player rather than revived from history.

For what is current, read
[`docs/notebooklm/Current-State.md`](docs/notebooklm/Current-State.md).

## Agent access

For project memory and architecture maps, start with `agent/AGENT-START.md`.
For an engineer taking over the code, read
[`docs/Fotty-Developer-Handoff.md`](docs/Fotty-Developer-Handoff.md) first. It
identifies the source baseline, module ownership, local checks and remaining
cleanup boundaries. A local source snapshot is not proof of an installed binary.

## Development
- iOS app: `Fotty.xcodeproj`
- Web companion and Cloudflare Worker: `web/`

The reviewed local toolchain is Xcode 27; the native deployment target is iOS
26.4. `project.yml` is the source configuration and the tracked Xcode project
uses explicit source membership. After moving or adding Swift files, run:

```bash
python3 -B tools/check_native_source_membership.py
```

For sequential, simulator-free logic tests and an unsigned iOS Release build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
FOTTY_XCODE_JOBS=1 ./tools/ios-ci.sh
```

The gate removes its owned DerivedData. Catalyst tests use freshly compiled
source, not the previously installed Mac app; they do not establish physical
iPhone or iPad acceptance. Signing, device installation and distribution are
separate gates.

The retired Android/TWA and homelab/P2P products are not part of this repository's supported graph.

## Documentation
- Current state: `docs/notebooklm/Current-State.md`
- Product Memory: `docs/notebooklm/Project-Memory.md`
- Decisions Log: `docs/notebooklm/Decisions-Log.md`

## Shorthand used in the notes

The dated notes use compact labels:

- **`Jet337`**: private build 337 installed on the owner's iPad ("Jet iPad").
- **`TestFlight338`**: build 338 shared through internal TestFlight.
- **Provider labels**: `CS` Community Sports, `AS` Additional (Plavio) Sports,
  `LS` CNC Sports, `FS` Flix Streams, `TV` reviewed TV, `HF` Highfly,
  `PP` PenguPlay. A number names the source position, so `CS2` is the second
  Community Sports stream.
- **`PR114`**: GitHub pull request 114.
