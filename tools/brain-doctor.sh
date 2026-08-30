#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Local project memory"
for path in \
  "$ROOT/docs/notebooklm/Project-Memory.md" \
  "$ROOT/docs/notebooklm/Decisions-Log.md" \
  "$ROOT/docs/notebooklm/Architecture-Map.md" \
  "$ROOT/docs/notebooklm/Risks.md" \
  "$ROOT/docs/notebooklm/Fotty-NotebookLM-Source.md"; do
  if [[ ! -s "$path" ]]; then
    echo "  error: missing or empty ${path#$ROOT/}" >&2
    exit 1
  fi
  echo "  ok: ${path#$ROOT/}"
done

if rg -n -i "homelab (is|remains) (current|active)|PocketBase Auth \(Internal\)|server/homelab-docker-compose" \
  "$ROOT/agent" "$ROOT/docs/notebooklm/Technical-Specs.md" "$ROOT/docs/notebooklm/Workflow.md" >/dev/null; then
  echo "  error: current documentation still claims retired infrastructure is active" >&2
  exit 1
fi

echo "[+] Fotty local memory is healthy."
