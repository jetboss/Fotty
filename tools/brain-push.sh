#!/usr/bin/env bash
set -euo pipefail

# This script pushes the latest project memory to the Homelab server for auto-indexing.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_HOST="100.116.91.102"
SERVER_USER="jelani"
REMOTE_PATH="~/acestream"

echo "[*] Refreshing local NotebookLM source..."
bash "$ROOT/tools/notebooklm-refresh.sh"

echo "[*] Syncing knowledge to server..."
scp -r "$ROOT/docs/notebooklm/"*.md "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/docs/notebooklm/"
scp -r "$ROOT/agent/"*.md "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/agent/"
scp -r "$ROOT/agent/playbooks/"*.md "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/agent/playbooks/"
scp -r "$ROOT/.cursor/rules/"*.mdc "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/.cursor/rules/"
scp "$ROOT/tools/brain/"*.py "$ROOT/tools/brain/README.md" "$SERVER_USER@$SERVER_HOST:$REMOTE_PATH/tools/brain/"

echo "[+] Done. The server's brain-monitor will now re-index the changes automatically."
echo "[i] Run ./tools/brain-doctor.sh to verify index health."
