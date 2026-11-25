# Isolated source connection tool

Current outcome and open gates: [Results](Results.md). The eight-module collection is complete; individual delivery and integration gates remain.

`tools/source-connection-test.py` runs the fixture-pinned native connection test
on an explicitly named physical iPad, using Fotty's actual source inventory,
existing enabled settings, accepted official fixture catalog, source resolvers,
guarded relay and AVPlayer decoded pixel buffers. It never enables sources,
imports arbitrary manifests or reconnects Watch. The inspection hook compiles
only underFOTTY_SOURCE_CONNECTION_TOOL; normal builds have no inspector entry.
There is no new product screen or source-routing change.

A live native qualification requires a fresh accepted fixture identity, current
independent ESPN in-progress status for exact UTC kickoff and both teams, an
actual currently admitted descriptor,90seconds of advancing decoded frames,
and separate contemporaneous programme observation. Native freshness follows
the existing30minute bound; status, conflict, TLS/public-IP, redirect, origin,
port, header and expiry rules remain. Unsupported sports, missing listings,
upstream HTTP failures, interrupted tests and decoded playback stay distinct.

Hosted WebKit checks abort inside XCTest in both tested configurations. Their
experimental observer and product hook were removed. Web entries now explicitly
require a manual ordinary-app check; neither a descriptor nor an unrun web gate
is a playback pass. The product web source is restored exactly to its pre-task
bytes. Old failed harness receipts are retained separately.

## Running a completed future batch

First confirm the named iPad is free and unlocked. Use one owned temporary
folder namedfotty-connection-tool.*; no phone or simulator is allowed.

```sh
python3 tools/source-connection-test.py \
  --gate "$FOTTY_CONNECTION_GATE" --device "$FOTTY_CONNECTION_IPAD" \
  --fixture "$FOTTY_CONNECTION_FIXTURE" --mode metadata --build \
  --report metadata.json

python3 tools/source-connection-test.py \
  --gate "$FOTTY_CONNECTION_GATE" --device "$FOTTY_CONNECTION_IPAD" \
  --fixture "$FOTTY_CONNECTION_FIXTURE" --mode playback \
  --report playback.json
```

Build once for the agreed batch; subsequent runs reuse those products. The
fixture must be a freshly corroborated sports-fixture:premier-league identity.
Optional--labels restricts physical holds, never source opt-ins. Only the exact
source-connection XCTest entry runs. Ordinary app background collection is
suppressed during hosted tests; empty Home there is intentional test isolation.

Reports retain opaque source labels, stages, HTTP/error codes, counts, timings
and public fixture identity. No media URLs, headers, tokens, signing details or
private preferences belong in receipts. Collection success/exit0 means the
matrix was collected, not that every provider played. The output separately
counts decoded holds and manual web gates. Programme review is still required.
Preserve redacted receipts before reusing a result name; clean only the owned
gate and keep-awake process on exit. Raw build/XCTest/private files are temporary.
