#!/usr/bin/env bash
set -euo pipefail

# Health check for the Fotty Brain. This is safe to run before any major agent task.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_HOST="${FOTTY_BRAIN_HOST:-100.116.91.102}"
SERVER_USER="${FOTTY_BRAIN_USER:-jelani}"
REMOTE_PATH="${FOTTY_BRAIN_REMOTE_PATH:-~/acestream}"
OLLAMA_HOST_REMOTE="${FOTTY_BRAIN_OLLAMA_HOST:-http://127.0.0.1:11434}"

echo "[*] Local project-memory sources"
test -s "$ROOT/docs/notebooklm/Fotty-NotebookLM-Source.md" && echo "  ok: generated source exists" || echo "  warn: generated source missing; run ./tools/notebooklm-refresh.sh"
test -s "$ROOT/tools/brain/.cache/knowledge.jsonl" && echo "  ok: local index has content" || echo "  info: local index is empty or missing; remote index may still be healthy"

echo "[*] Remote SSH"
if ! ssh -o BatchMode=yes -o ConnectTimeout=1 "$SERVER_USER@$SERVER_HOST" "true" 2>/dev/null; then
  echo "  info: homelab ($SERVER_USER@$SERVER_HOST) is retired/offline. Local memory is primary."
  echo "[+] Fotty local memory is healthy."
  exit 0
fi
echo "  ok: $SERVER_USER@$SERVER_HOST reachable"

echo "[*] Remote index"
ssh "$SERVER_USER@$SERVER_HOST" "cd $REMOTE_PATH && test -s tools/brain/.cache/knowledge.jsonl && wc -l tools/brain/.cache/knowledge.jsonl"

echo "[*] Ollama models"
ssh "$SERVER_USER@$SERVER_HOST" "export OLLAMA_HOST=$OLLAMA_HOST_REMOTE; python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen('$OLLAMA_HOST_REMOTE/api/tags', timeout=10) as resp:
    data = json.load(resp)
names = sorted(model.get('name', '') for model in data.get('models', []))
required = ['nomic-embed-text:latest', 'qwen2.5:3b']
missing = [name for name in required if name not in names]
print('  models:', ', '.join(names) or '(none)')
if missing:
    raise SystemExit('missing required models: ' + ', '.join(missing))
PY"

echo "[*] Smoke query"
"$ROOT/tools/ask-brain.sh" "Return the path of the Fotty project memory file." >/tmp/fotty-brain-doctor.out
grep -q "docs/notebooklm" /tmp/fotty-brain-doctor.out
echo "  ok: retrieval returned project-memory context"

echo "[+] Fotty Brain is healthy."
