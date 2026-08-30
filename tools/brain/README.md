# Local Brain tools (private RAG)

- `embed_index.py` — embeds `docs/notebooklm/NotebookLM-Source.md` (or individual `docs/notebooklm/*.md` if the bundle is missing), `agent/*.md`, and `.cursorrules` via Ollama `/api/embeddings`.
- `query_brain.py` — cosine retrieval over `tools/brain/.cache/knowledge.jsonl`; optional `--synthesize` uses Ollama `/v1/chat/completions`.
- `../private-kb-sync.sh` — canonical full refresh: regenerate source, push docs, rebuild remote index.
- `../brain-doctor.sh` — health check for SSH, index content, Ollama models, and smoke retrieval.
- `../agent-start.sh` — pre-work mission brief for agents.
- `../agent-finish.sh` — post-work memory, verification, and brain-sync checklist.

Environment:

- `OLLAMA_HOST` — default `http://127.0.0.1:11434` (use an SSH tunnel or LAN URL).
- `OV_AI_CHAT_MODEL` — chat model tag for `--synthesize` (default `qwen2.5:3b`).

See `agent/OPERATOR.md` for the full stack.
