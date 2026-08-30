#!/usr/bin/env bash
# Reset Fotty PocketBase superuser on the homelab (requires Tailscale / LAN).
#
# Usage:
#   ./tools/pb-superuser-reset.sh [email] [new_password]
#
# Defaults: admin@pixel-invoice.com  (password prompted if omitted)

set -euo pipefail

HOST="${FOTTY_BRAIN_HOST:-100.116.91.102}"
EMAIL="${1:-admin@pixel-invoice.com}"
PASSWORD="${2:-}"

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "New PocketBase superuser password: " PASSWORD
  echo
fi

echo "Connecting to ${HOST}…"
ssh -o ConnectTimeout=15 "${FOTTY_SSH_USER:-jelani}@${HOST}" \
  "cd /home/jelani/pocketbase && ./pocketbase admin update '${EMAIL}' '${PASSWORD}'"

echo "Done. Test login at https://fotty-api.pixel-invoice.com/_/"
echo "Then: cd web && PB_ADMIN_EMAIL=${EMAIL} PB_ADMIN_PASSWORD='***' npm run pb:admin-setup"
