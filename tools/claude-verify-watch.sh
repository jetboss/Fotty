#!/usr/bin/env bash
# Start once in a Terminal window; stop with Ctrl-C.
# Waits for an agent to drop logs/.verify-request in the project folder, then
# pushes the current branch (never main) and runs tools/claude-verify.sh.
# It runs only these two fixed steps. Results land in logs/verify-latest.log.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p logs
REQUEST="logs/.verify-request"
echo "Watching for verify requests in $ROOT_DIR (Ctrl-C to stop)..."
while true; do
  if [[ -e "$REQUEST" ]]; then
    rm -f "$REQUEST"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    echo
    echo "== $(date '+%H:%M:%S') request received on $branch"
    if [[ "$branch" != "main" ]]; then
      git push -q -u origin "$branch" 2>&1 | tail -2 || echo "push failed (continuing to verify)"
    fi
    # Keep the Mac awake only while the build runs.
    caffeinate -i bash tools/claude-verify.sh
    echo "== $(date '+%H:%M:%S') done; waiting for the next request"
  fi
  sleep 5
done
