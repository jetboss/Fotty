#!/usr/bin/env bash
# Rebuild and restart fotty-p2p-proxy on homelab (scraper.pixel-invoice.com → :8006).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${FOTTY_P2P_DEPLOY_HOST:-jelani@100.116.91.102}"
REMOTE_SERVER_DIR="${FOTTY_P2P_REMOTE_SERVER_DIR:-~/acestream/server}"

echo "Syncing P2P proxy sources → ${HOST}:${REMOTE_SERVER_DIR}…"
rsync -az \
  "${ROOT_DIR}/server/p2p_proxy_service.py" \
  "${ROOT_DIR}/server/p2p_config.py" \
  "${ROOT_DIR}/server/p2p_proxy_core.py" \
  "${ROOT_DIR}/server/p2p_scraper_queries.py" \
  "${ROOT_DIR}/server/p2p_pinned_channels.py" \
  "${ROOT_DIR}/server/p2p_pinned_channels.json" \
  "${ROOT_DIR}/server/Dockerfile.p2p-proxy" \
  "${ROOT_DIR}/server/homelab-docker-compose.yml" \
  "${HOST}:${REMOTE_SERVER_DIR}/"

echo "Building broker image and applying the canonical Compose stack…"
ssh "$HOST" 'set -e
cd ~/acestream/server
for env_file in ~/acestream/.env ~/acestream/server/.env ~/fotty-web-deploy/.env; do
  if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
    break
  fi
done
: "${P2P_API_PASSWORD:?Missing P2P_API_PASSWORD on homelab (.env)}"
docker build -f Dockerfile.p2p-proxy -t fotty-p2p-proxy:latest .
docker rm -f fotty-p2p-proxy 2>/dev/null || true
docker compose -p acestream -f homelab-docker-compose.yml up -d acestream-engine p2p-redis fotty-p2p-proxy

curl --fail --silent --show-error --retry 12 --retry-delay 2 \
  http://127.0.0.1:8006/health | python3 -m json.tool
count=$(curl -sf -H "Authorization: Bearer ${P2P_API_PASSWORD}" http://127.0.0.1:8006/matches | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo "matches count=${count}"

if ss -ltn | awk '"'"'$4 ~ /:(6379|6878|8006)$/ && $4 !~ /(127\.0\.0\.1|\[::1\]):/ { print; exposed=1 } END { exit exposed }'"'"'; then
  echo "P2P control services are loopback-only."
else
  echo "Refusing successful deploy: a P2P control service is listening beyond loopback." >&2
  echo "Firewall TCP 6379, 6878, and 8006 before exposing this host." >&2
  exit 1
fi
'

echo "Done. Public catalog access now requires broker authorization."
