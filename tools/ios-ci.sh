#!/usr/bin/env bash
# Deterministic GitHub/local iOS gate. Never boots a simulator, signs an app,
# installs to a device, or retains DerivedData that it created.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_JOBS="${FOTTY_XCODE_JOBS:-2}"
OWNS_DERIVED_DATA=0

if ! [[ "$XCODE_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FOTTY_XCODE_JOBS must be a positive integer." >&2
  exit 2
fi

if [[ -n "${FOTTY_CI_DERIVED_DATA:-}" ]]; then
  DERIVED_DATA="$FOTTY_CI_DERIVED_DATA"
else
  TEMP_PARENT="${RUNNER_TEMP:-/private/tmp}"
  DERIVED_DATA="$(mktemp -d "$TEMP_PARENT/FottyCI.XXXXXX")"
  OWNS_DERIVED_DATA=1
fi

cleanup() {
  [[ "$OWNS_DERIVED_DATA" -eq 1 ]] || return 0
  case "$DERIVED_DATA" in
    "${RUNNER_TEMP:-/private/tmp}"/FottyCI.*)
      [[ ! -e "$DERIVED_DATA" ]] || find "$DERIVED_DATA" -depth -delete
      ;;
    *)
      echo "Refusing unexpected CI cleanup target: $DERIVED_DATA" >&2
      return 1
      ;;
  esac
}
trap cleanup EXIT INT TERM

cd "$ROOT_DIR"

node tools/generate-football-competition-catalog.mjs --check
node tools/audit-provider-football-identity.mjs

if rg -n '(APP_REVIEW_SAFE|ReviewSafe|Info-ReviewSafe|IntegrityService|LicenseManager|Field Events|Division A|Series C)' \
  Fotty project.yml Fotty.xcodeproj/project.pbxproj; then
  echo "Retired review-safe code or vocabulary is present in the production graph." >&2
  exit 1
fi

xcodebuild build-for-testing \
  -quiet \
  -project Fotty.xcodeproj \
  -scheme Fotty \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$DERIVED_DATA" \
  -jobs "$XCODE_JOBS" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:FottyTests

xcodebuild test-without-building \
  -quiet \
  -project Fotty.xcodeproj \
  -scheme Fotty \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$DERIVED_DATA" \
  -jobs "$XCODE_JOBS" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:FottyTests

xcodebuild build \
  -quiet \
  -project Fotty.xcodeproj \
  -scheme Fotty \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -jobs "$XCODE_JOBS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

echo "Simulator-free iOS CI gate passed."
