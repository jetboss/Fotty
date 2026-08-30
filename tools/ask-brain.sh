#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -eq 0 ]]; then
  echo 'Usage: ./tools/ask-brain.sh "Your question here"'
  exit 1
fi

QUESTION="$*"
FILES=(
  "$ROOT/docs/notebooklm/Project-Memory.md"
  "$ROOT/docs/notebooklm/Decisions-Log.md"
  "$ROOT/docs/notebooklm/Architecture-Map.md"
  "$ROOT/docs/notebooklm/Risks.md"
  "$ROOT/docs/notebooklm/QA-Playbook.md"
  "$ROOT/agent/AGENT-START.md"
)

terms="$(
  printf '%s' "$QUESTION" |
    tr '[:upper:]' '[:lower:]' |
    tr -cs '[:alnum:]' '\n' |
    awk 'length($0) >= 4 && !seen[$0]++' |
    sed -n '1,8p'
)"

echo "[*] Searching Fotty local project memory..."
if [[ -z "$terms" ]]; then
  sed -n '1,80p' "$ROOT/docs/notebooklm/Project-Memory.md"
  exit 0
fi

results="$(
  while IFS= read -r term; do
    rg -n -i -F --max-count 8 "$term" "${FILES[@]}" || true
  done <<< "$terms" |
    awk '!seen[$0]++' |
    sed -n '1,80p'
)"

if [[ -n "$results" ]]; then
  printf '%s\n' "$results"
else
  echo "No exact local-memory matches. Read docs/notebooklm/Project-Memory.md and Architecture-Map.md."
fi
