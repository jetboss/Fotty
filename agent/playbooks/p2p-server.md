# P2P Server Playbook

Use this when touching the homelab broker, proxy, manifest generation, warmup behavior, Docker compose, or server-side stream health. (Server-side EPG/XMLTV was removed with the retired homelab guide pipeline.)

## Read First

- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Risks.md`
- `server/README_P2P_PROXY.md`
- `server/homelab-docker-compose.yml`
- `server/p2p_proxy_service.py`
- `server/p2p_proxy_core.py`
- `server/tests/test_p2p_proxy_service.py`

## Standing Decisions

- P2P is a resilient fallback, not a reason to block the whole player.
- Reuse warm sessions when available.
- Keep server behavior observable through explicit health/progress states.
- Keep `GUNICORN_WORKERS=1` unless the concurrency model is deliberately redesigned.
- Do not expose secrets, raw stream URLs, or private provider internals in docs or user-visible errors.

## Common Failure Points

- Cold P2P startup exceeding the user’s patience window.
- Stale manifests or segment authorization mismatches after session reuse.
- Background work continuing after the client has moved to another source.
- Compose changes that desync the homelab from local scripts.
- Logs or generated memory docs accidentally containing private URLs.

## Verification

- Run focused Python tests for changed proxy behavior.
- Confirm warm source reuse still works.
- Confirm failed P2P source returns useful state instead of hanging.
- Re-run `./tools/brain-doctor.sh` after homelab script or compose changes.

## Brain Prompts

```bash
./tools/ask-brain.sh "What P2P broker decisions affect this change?"
./tools/ask-brain.sh "What are the known P2P startup and warm-session risks?"
```
