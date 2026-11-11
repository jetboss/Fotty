#!/usr/bin/env bash
# Uploads a signed archive to internal TestFlight with the App Store Connect
# Xcode account, sets its "What to Test" note (API key) and adds it to the internal group
# (TESTFLIGHT_GROUP, default "Fotty Internal Smoke"), which notifies its
# testers. Each upload still needs the
# owner's explicit go-ahead (docs/notebooklm/Workflow.md).
#
#   tools/testflight-upload.sh <path/to/Fotty.xcarchive> "Bug fixes"
#   tools/testflight-upload.sh --check <path/to/Fotty.xcarchive>   # read-only lookup
#
# Uses the same variables as owner-tools/testflight-usage-sync, loaded from
# the gitignored .env.asc.local: APP_STORE_CONNECT_ISSUER_ID (required),
# APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_PRIVATE_KEY_PATH (optional
# when exactly one AuthKey_*.p8 is in ~/.appstoreconnect/private_keys).
# The key is passed by path only; nothing here prints it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
if [[ "${1:-}" == "--check" ]]; then CHECK=1; shift; fi
ARCHIVE="${1:-}"
NOTES="${2:-}"
[[ -d "$ARCHIVE" && "$ARCHIVE" == *.xcarchive ]] || { echo "Usage: $0 [--check] <archive.xcarchive> [\"What to Test\"]" >&2; exit 2; }
[[ "$CHECK" -eq 1 || -n "$NOTES" ]] || { echo "Give the What to Test note as the second argument." >&2; exit 2; }

ENV_FILE="$ROOT_DIR/.env.asc.local"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE with APP_STORE_CONNECT_ISSUER_ID." >&2; exit 2; }
set -a; source "$ENV_FILE"; set +a
[[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] || { echo "APP_STORE_CONNECT_ISSUER_ID is empty in $ENV_FILE." >&2; exit 2; }

KEY_FILE="${APP_STORE_CONNECT_PRIVATE_KEY_PATH:-}"
if [[ -z "$KEY_FILE" ]]; then
  KEY_DIR="$HOME/.appstoreconnect/private_keys"
  if [[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
    KEY_FILE="$KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  else
    shopt -s nullglob
    KEYS=("$KEY_DIR"/AuthKey_*.p8)
    shopt -u nullglob
    [[ ${#KEYS[@]} -eq 1 ]] || { echo "Set APP_STORE_CONNECT_KEY_ID: found ${#KEYS[@]} keys in $KEY_DIR." >&2; exit 2; }
    KEY_FILE="${KEYS[0]}"
  fi
fi
[[ -f "$KEY_FILE" ]] || { echo "No App Store Connect key file at the configured path." >&2; exit 2; }
KEY_ID="$(basename "$KEY_FILE" .p8)"; KEY_ID="${APP_STORE_CONNECT_KEY_ID:-${KEY_ID#AuthKey_}}"
export APP_STORE_CONNECT_KEY_ID="$KEY_ID" APP_STORE_CONNECT_PRIVATE_KEY_PATH="$KEY_FILE"

PLIST="$ARCHIVE/Products/Applications/Fotty.app/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
NOTES_TOOL=(node "$ROOT_DIR/tools/asc-testflight-notes.mjs" --bundle-id "$BUNDLE_ID" --version "$VERSION" --build "$BUILD")

if [[ "$CHECK" -eq 1 ]]; then
  "${NOTES_TOOL[@]}" --check
  exit 0
fi

EXPORT_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/FottyExport.XXXXXX")"
trap 'find "$EXPORT_DIR" -depth -delete' EXIT

# Distribution signing uses the Apple Account signed in to Xcode (cloud
# signing): Xcode reports this API key's role as unsupported for signing.
# Set TESTFLIGHT_SIGN_WITH_KEY=1 to try the key instead.
SIGNING_AUTH=()
if [[ "${TESTFLIGHT_SIGN_WITH_KEY:-0}" == "1" ]]; then
  SIGNING_AUTH=(-authenticationKeyPath "$KEY_FILE" -authenticationKeyID "$KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")
fi
echo "Uploading $BUNDLE_ID $VERSION ($BUILD) to internal TestFlight..."
set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT_DIR/ExportOptions-TestFlightInternal.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  ${SIGNING_AUTH[@]+"${SIGNING_AUTH[@]}"} \
  > "$EXPORT_DIR/export.log" 2>&1
STATUS=$?
set -e
grep -E "error:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)" "$EXPORT_DIR/export.log" || true
[[ "$STATUS" -eq 0 ]] || { echo "Upload failed." >&2; exit 1; }

# Apple processes a new build for roughly 5–30 minutes before notes can be set.
"${NOTES_TOOL[@]}" --notes "$NOTES" --group "${TESTFLIGHT_GROUP:-Fotty Internal Smoke}" --wait 2700
