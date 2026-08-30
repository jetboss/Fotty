#!/usr/bin/env bash
# Build Fotty for an iOS Simulator (default: iPhone 17 on latest installed 26.x).
# Override: DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' ./tools/ios-simulator-build.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Fotty.xcodeproj"
SCHEME="${SCHEME:-Fotty}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEST="${DEST:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
IOS_ENV_FILE="${IOS_ENV_FILE:-$ROOT_DIR/.env.ios.local}"

if [[ -f "$IOS_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$IOS_ENV_FILE"
  set +a
fi

SECRET_BUILD_SETTINGS=(
  "FOOTBALL_DATA_API_KEY=${FOOTBALL_DATA_API_KEY:-}"
  "RAPID_API_KEY=${RAPID_API_KEY:-}"
  "API_FOOTBALL_KEY=${API_FOOTBALL_KEY:-}"
)

echo "Building $SCHEME ($CONFIGURATION) for: $DEST"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DEST" \
  "${SECRET_BUILD_SETTINGS[@]}" \
  build
