#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Refreshing local project-memory bundle..."
bash "$ROOT/tools/notebooklm-refresh.sh"
echo "[+] Local project memory refreshed. Remote homelab sync is retired."
