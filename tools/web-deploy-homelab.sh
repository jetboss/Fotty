#!/usr/bin/env bash
# Deploy Fotty Web to homelab (jelani@100.116.91.102:~/fotty-web-deploy).
# NEVER syncs .env — production secrets stay on the server.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${FOTTY_WEB_DEPLOY_HOST:-jelani@100.116.91.102}"
REMOTE_DIR="${FOTTY_WEB_DEPLOY_DIR:-~/fotty-web-deploy}"
REQUIRE_CI_GREEN="${FOTTY_WEB_REQUIRE_CI_GREEN:-0}"

if [[ "$REQUIRE_CI_GREEN" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh is required when FOTTY_WEB_REQUIRE_CI_GREEN=1" >&2
    exit 1
  fi
  echo "Checking latest GitHub Actions Web workflow on HEAD…"
  branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
  sha="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  conclusion="$(gh run list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --branch "$branch" --workflow Web --limit 20 --json headSha,conclusion,status \
    --jq ".[] | select(.headSha==\"$sha\") | .conclusion" | head -n1 || true)"
  if [[ -z "$conclusion" ]]; then
    echo "ERROR: No completed Web workflow found for $sha. Push and wait for CI, or set FOTTY_WEB_REQUIRE_CI_GREEN=0." >&2
    exit 1
  fi
  if [[ "$conclusion" != "success" ]]; then
    echo "ERROR: Web workflow conclusion for $sha is '$conclusion' (need success)." >&2
    exit 1
  fi
  echo "CI green for $sha"
fi

echo "Syncing web/ → ${HOST}:${REMOTE_DIR} (excluding .env)…"
rsync -az --delete \
  --exclude 'node_modules' \
  --exclude '.next' \
  --exclude 'test-results' \
  --exclude '.turbo' \
  --exclude '.env' \
  --exclude '.env.local' \
  --exclude '.env.*.local' \
  "${ROOT_DIR}/web/" \
  "${HOST}:${REMOTE_DIR}/"

echo "Building and restarting fotty-web…"
ssh "$HOST" 'set -e
cd ~/fotty-web-deploy
test -f .env || { echo "Missing ~/fotty-web-deploy/.env — restore secrets before deploy."; exit 1; }
if grep -qE "^[[:space:]]*NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH=true" .env; then
  echo "ERROR: Remove NEXT_PUBLIC_FOTTY_ALLOW_LOCAL_AUTH=true from ~/fotty-web-deploy/.env (local auth is blocked in production)."
  exit 1
fi
if grep -qE "^[[:space:]]*FOTTY_PREVIEW_ROUTES_ENABLED=true" .env; then
  echo "WARN: FOTTY_PREVIEW_ROUTES_ENABLED=true in .env — preview routes are blocked in production builds anyway."
fi
if ! grep -qE "^[[:space:]]*FOTTY_WATCH_STREAM_SECRET=.+" .env; then
  echo "ERROR: Set FOTTY_WATCH_STREAM_SECRET in ~/fotty-web-deploy/.env (dedicated watch token secret; not billing webhook)."
  exit 1
fi
v2_enabled=$(grep -E "^[[:space:]]*NEXT_PUBLIC_FOTTY_V2_ENABLED=" .env | tail -n1 | cut -d= -f2- | tr -d "\"'"'"'" || true)
site_url=$(grep -E "^[[:space:]]*NEXT_PUBLIC_SITE_URL=" .env | tail -n1 | cut -d= -f2- | tr -d "\"'"'"'" || true)
if [ "${v2_enabled}" = "true" ]; then
  echo "Building with NEXT_PUBLIC_FOTTY_V2_ENABLED=true"
else
  echo "WARN: NEXT_PUBLIC_FOTTY_V2_ENABLED is not true — public site will stay on classic shell."
fi
docker build \
  --build-arg "NEXT_PUBLIC_FOTTY_V2_ENABLED=${v2_enabled:-false}" \
  --build-arg "NEXT_PUBLIC_SITE_URL=${site_url}" \
  -t fotty-web:latest .
docker rm -f fotty-web 2>/dev/null || true
docker run -d --name fotty-web --restart unless-stopped \
  -p 127.0.0.1:3010:3000 \
  -v ~/fotty-web-deploy/.data:/app/.data \
  --env-file ~/fotty-web-deploy/.env \
  fotty-web:latest
sleep 2
curl -sf -o /dev/null http://127.0.0.1:3010/api/matches && echo "ok /api/matches"
configured=$(curl -sf "http://127.0.0.1:3010/api/football/standings?league=premierLeague" | python3 -c "import sys,json; print(json.load(sys.stdin).get(\"configured\"))" 2>/dev/null || echo false)
echo "standings configured=${configured}"
'

echo "Done. Public URL: https://fotty.pixel-invoice.com"
