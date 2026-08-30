#!/usr/bin/env bash
set -euo pipefail

# Canonical command for refreshing the Fotty Brain from the current repo state.
# Local docs are regenerated, pushed to the homelab, then indexed on the server.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_HOST="${FOTTY_BRAIN_HOST:-100.116.91.102}"
SERVER_USER="${FOTTY_BRAIN_USER:-jelani}"
REMOTE_PATH="${FOTTY_BRAIN_REMOTE_PATH:-~/acestream}"
OLLAMA_HOST_REMOTE="${FOTTY_BRAIN_OLLAMA_HOST:-http://127.0.0.1:11434}"

echo "[*] Refreshing local project-memory bundle..."
bash "$ROOT/tools/notebooklm-refresh.sh"

if ! ssh -o ConnectTimeout=1 -o BatchMode=yes "$SERVER_USER@$SERVER_HOST" "true" 2>/dev/null; then
  echo "[!] Homelab brain ($SERVER_HOST) is offline/retired. Skipping remote index sync."
  exit 0
fi

echo "[*] Syncing safe knowledge sources to $SERVER_USER@$SERVER_HOST:$REMOTE_PATH..."
ssh "$SERVER_USER@$SERVER_HOST" "mkdir -p $REMOTE_PATH/docs/notebooklm $REMOTE_PATH/agent/playbooks $REMOTE_PATH/.cursor/rules $REMOTE_PATH/tools/brain"
scp "$ROOT/docs/notebooklm/"*.md "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/docs/notebooklm/"
scp "$ROOT/agent/"*.md "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/agent/"
if compgen -G "$ROOT/agent/playbooks/*.md" >/dev/null; then
  scp "$ROOT/agent/playbooks/"*.md "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/agent/playbooks/"
fi
if compgen -G "$ROOT/.cursor/rules/*.mdc" >/dev/null; then
  scp "$ROOT/.cursor/rules/"*.mdc "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/.cursor/rules/"
fi
if [[ -f "$ROOT/AGENTS.md" ]]; then
  scp "$ROOT/AGENTS.md" "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/AGENTS.md"
fi
scp "$ROOT/tools/brain/"*.py "$ROOT/tools/brain/README.md" "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/tools/brain/"
scp "$ROOT/tools/ask-brain.sh" "$ROOT/tools/brain-doctor.sh" "$ROOT/tools/private-kb-sync.sh" "$ROOT/tools/agent-start.sh" "$ROOT/tools/agent-finish.sh" "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/tools/"
ssh "$SERVER_USER@$SERVER_HOST" "chmod +x $REMOTE_PATH/tools/ask-brain.sh $REMOTE_PATH/tools/brain-doctor.sh $REMOTE_PATH/tools/private-kb-sync.sh $REMOTE_PATH/tools/agent-start.sh $REMOTE_PATH/tools/agent-finish.sh"

echo "[*] Rebuilding remote semantic index..."
ssh "$SERVER_USER@$SERVER_HOST" "export OLLAMA_HOST=$OLLAMA_HOST_REMOTE; cd $REMOTE_PATH && python3 tools/brain/embed_index.py"

echo "[+] Fotty Brain sync complete."
