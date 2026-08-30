# Fotty Workflow

## Human-AI Loop
1. **Identify**: User identifies a stability or data issue.
2. **Research**: Agent uses `grep_search` and `view_file` to find the root cause.
3. **Reason**: Agent consults `docs/notebooklm/` to ensure the fix aligns with architecture.
4. **Deploy**: Use `tools/ios-deploy-device.sh` for physical device verification.
5. **Log**: Record the change in `Decisions-Log.md`.

## Testing Protocol (Ready for v1.6)
Before push:
- [ ] Sub-10s startup for verified web sources.
- [ ] P2P fallback resolution below the player.
- [ ] PiP stability during swipe-up.
- [ ] Branding fidelity (logos present for all Big 5 + NBA/WNBA).
- [ ] PocketBase sync reliability (no silent decoding crashes).

## Agent Hand-off
All agents must read `agent/AGENT-START.md` before initiating changes.
After significant changes, run:
```bash
./tools/notebooklm-refresh.sh
```
