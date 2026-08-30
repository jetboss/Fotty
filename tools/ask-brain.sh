#!/usr/bin/env bash
set -euo pipefail

# This script is your portal to the "Fotty Brain". 
# It works like NotebookLM: Ask a question, get advice based on your private docs.

SERVER_HOST="100.116.91.102"
SERVER_USER="jelani"
REMOTE_PATH="~/acestream"

if [ $# -eq 0 ]; then
    echo "Usage: ./tools/ask-brain.sh \"Your question here\""
    exit 1
fi

QUESTION="$*"

echo -e "\033[1;34m[*] Consulting the Fotty Brain...\033[0m"

if ! ssh -o ConnectTimeout=1 -o BatchMode=yes "$SERVER_USER@$SERVER_HOST" "true" 2>/dev/null; then
    echo "[!] Homelab brain is offline. Relying on local durable memory in docs/notebooklm/."
    exit 0
fi

# We run the query on the server and use the --synthesize flag to get the "Advice" mode.
printf '%s' "$QUESTION" | ssh -o ConnectTimeout=2 "$SERVER_USER@$SERVER_HOST" 'QUESTION=$(cat); export OLLAMA_HOST=http://127.0.0.1:11434; cd ~/acestream && python3 tools/brain/query_brain.py "$QUESTION" --synthesize'
