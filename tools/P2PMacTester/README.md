# P2P Mac Tester

Small macOS command-line tester for Fotty P2P/AceStream debugging.

Run from the repository root:

```sh
./tools/p2p-mac-test status
./tools/p2p-mac-test browse --limit 15
./tools/p2p-mac-test search "nba" --probe --limit 5
./tools/p2p-mac-test probe --cid <acestream-id> --watch 30
./tools/p2p-mac-test play --cid <acestream-id> --player IINA
```

What it checks:

- scraper catalog/search responses
- P2P proxy health
- HLS manifest response
- first media segment response and byte count
- optional status polling for peers, speed, buffer, and ready segments
- optional handoff to a Mac player through `open`

The tester is intentionally separate from the iOS app target so P2P fixes can be tested without changing which app is installed on the phone.
