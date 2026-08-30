# Agent instructions (Fotty)

Dedicated **`agent/`** folder: onboarding and homelab operator docs **separate** from app source (`Fotty/`) and NotebookLM memory (`docs/notebooklm/`).

- **Onboarding / where to write project docs:** **`agent/AGENT-START.md`**
- **Homelab (Ollama, Tailscale, WebUI):** **`agent/OPERATOR.md`**
- **Repo root pointer:** **`AGENTS.md`** (one line → here)
- **Cursor rule:** **`.cursor/rules/private-knowledge-base.mdc`**

## Reliability Standard

Agents should treat the Fotty Brain as required context for:

- architecture answers
- major feature work
- release-readiness checks
- debugging that touches playback, P2P, data providers, social/cloud sync, or app navigation

Use:

```bash
./tools/agent-start.sh "Describe the task"
```

After significant work:

```bash
./tools/agent-finish.sh "Describe what changed"
```
