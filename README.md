# Fotty Sports Hub

Fotty is an iOS-first live sports companion with match-day discovery, optional
third-party playback, personal Matchday planning and an FPL decision workspace.

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
- Product Memory: `docs/notebooklm/Project-Memory.md`
- Decisions Log: `docs/notebooklm/Decisions-Log.md`
