#!/usr/bin/env bash
set -euo pipefail

PROJECT="/Users/jelani/Documents/Development/Fotty/Fotty.xcodeproj"
SCHEME="Fotty"
CONFIGURATION="Debug"
DESTINATION="platform=macOS,variant=Mac Catalyst"
OPEN_APP=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --destination)
      DESTINATION="$2"
      shift 2
      ;;
    --no-open)
      OPEN_APP=0
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "Building $SCHEME for $DESTINATION..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  build

BUILD_SETTINGS="$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -showBuildSettings 2>/dev/null
)"

TARGET_BUILD_DIR="$(awk -F' = ' '/TARGET_BUILD_DIR = / {print $2; exit}' <<<"$BUILD_SETTINGS")"
FULL_PRODUCT_NAME="$(awk -F' = ' '/FULL_PRODUCT_NAME = / {print $2; exit}' <<<"$BUILD_SETTINGS")"

if [[ -z "$TARGET_BUILD_DIR" || -z "$FULL_PRODUCT_NAME" ]]; then
  echo "Could not determine built app path." >&2
  exit 1
fi

APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
echo "Built app: $APP_PATH"

if [[ $OPEN_APP -eq 1 ]]; then
  echo "Launching app..."
  open "$APP_PATH"
fi
