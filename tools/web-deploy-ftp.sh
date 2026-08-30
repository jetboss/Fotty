#!/usr/bin/env bash
# Deploy static getfotty.com via Octavia FTP.
# Requires: FOTTY_FTP_PASSWORD in the environment (never commit it).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="${ROOT_DIR}/web"
OUT_DIR="${WEB_DIR}/out"
HOST="${FOTTY_FTP_HOST:-ftp.octavianetworks.com}"
USER="${FOTTY_FTP_USER:-jet@getfotty.com}"
API_BASE="${NEXT_PUBLIC_FOTTY_API_BASE:-https://fotty-playback-v3.adaptive-rhubarb.workers.dev}"

restore_dynamic_routes() {
  while IFS= read -r -d '' route_file; do
    if grep -q 'export const dynamic = "force-static"' "$route_file"; then
      if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' 's/export const dynamic = "force-static"/export const dynamic = "force-dynamic"/' "$route_file"
      else
        sed -i 's/export const dynamic = "force-static"/export const dynamic = "force-dynamic"/' "$route_file"
      fi
    fi
  done < <(find "${WEB_DIR}/src/app/api" -name 'route.ts' -print0)
}

# A failed or interrupted static build must not leave runtime API routes in
# static-export mode in the source tree.
trap restore_dynamic_routes EXIT

if [[ -z "${FOTTY_FTP_PASSWORD:-}" ]]; then
  echo "ERROR: Set FOTTY_FTP_PASSWORD before deploying." >&2
  exit 1
fi

echo "Building static site with playback Worker ${API_BASE}…"
cd "${WEB_DIR}"
NEXT_PUBLIC_SITE_URL="${NEXT_PUBLIC_SITE_URL:-https://getfotty.com}" \
NEXT_PUBLIC_FOTTY_API_BASE="${API_BASE}" \
NEXT_PUBLIC_FOTTY_V2_ENABLED="${NEXT_PUBLIC_FOTTY_V2_ENABLED:-true}" \
npm run build:static
restore_dynamic_routes

if [[ ! -f "${OUT_DIR}/index.html" ]]; then
  echo "ERROR: ${OUT_DIR}/index.html missing after build." >&2
  exit 1
fi

echo "Uploading ${OUT_DIR} → ${HOST}…"
python3 - <<PY
import ftplib, os
from pathlib import Path

host = os.environ.get("FOTTY_FTP_HOST", "${HOST}")
user = os.environ.get("FOTTY_FTP_USER", "${USER}")
password = os.environ["FOTTY_FTP_PASSWORD"]
local_root = Path("${OUT_DIR}")

ftp = ftplib.FTP(host, timeout=120)
ftp.login(user, password)
print("PWD:", ftp.pwd())

def ftp_makedirs(remote_dir: str):
    ftp.cwd("/")
    if not remote_dir:
        return
    for part in [p for p in remote_dir.split("/") if p]:
        try:
            ftp.cwd(part)
        except ftplib.error_perm:
            ftp.mkd(part)
            ftp.cwd(part)

uploaded = 0
failed = []
for file_path in sorted(local_root.rglob("*")):
    if not file_path.is_file():
        continue
    rel = file_path.relative_to(local_root).as_posix()
    remote_dir = os.path.dirname(rel)
    remote_name = os.path.basename(rel)
    try:
        ftp_makedirs(remote_dir)
        with open(file_path, "rb") as fh:
            ftp.storbinary(f"STOR {remote_name}", fh)
        uploaded += 1
        if uploaded % 100 == 0:
            print(f"... {uploaded} files")
    except Exception as exc:
        failed.append((rel, str(exc)))

ftp.quit()
print(f"uploaded={uploaded} failed={len(failed)}")
for rel, err in failed[:20]:
    print("FAIL", rel, err)
if failed:
    raise SystemExit(1)
PY

echo "Deploy complete."
