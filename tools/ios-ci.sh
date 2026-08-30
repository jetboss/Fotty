#!/usr/bin/env bash
# Deterministic GitHub/local iOS gate. Never boots a simulator, signs an app,
# installs to a device, or retains DerivedData that it created.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_JOBS="${FOTTY_XCODE_JOBS:-2}"
OWNS_DERIVED_DATA=0
# Keep this array non-empty for the Bash 3.2 shipped with macOS; under `set -u`,
# expanding an empty array raises an unbound-variable error.
CATALYST_BUILD_SETTINGS=("FOTTY_CI=1")

if ! [[ "$XCODE_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FOTTY_XCODE_JOBS must be a positive integer." >&2
  exit 2
fi

if [[ -n "${FOTTY_CATALYST_DEPLOYMENT_TARGET:-}" ]]; then
  if ! [[ "$FOTTY_CATALYST_DEPLOYMENT_TARGET" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "FOTTY_CATALYST_DEPLOYMENT_TARGET must be a numeric version." >&2
    exit 2
  fi
  # GitHub's Xcode 27 image can temporarily trail the latest macOS beta.
  # This override applies only to Catalyst unit tests; the generic iOS
  # Release build below retains the project's real deployment target.
  CATALYST_BUILD_SETTINGS+=(
    "IPHONEOS_DEPLOYMENT_TARGET=$FOTTY_CATALYST_DEPLOYMENT_TARGET"
    "MACOSX_DEPLOYMENT_TARGET=$FOTTY_CATALYST_DEPLOYMENT_TARGET"
  )
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

finish() {
  local exit_code=$?
  local cleanup_code=0
  trap - EXIT INT TERM
  set +e
  cleanup
  cleanup_code=$?
  if [[ "$cleanup_code" -ne 0 ]]; then
    [[ "$exit_code" -ne 0 ]] || exit_code="$cleanup_code"
  fi
  exit "$exit_code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$ROOT_DIR"

node tools/generate-football-competition-catalog.mjs --check
node tools/audit-provider-football-identity.mjs

RETIRED_PATTERN='(APP_REVIEW_SAFE|ReviewSafe|Info-ReviewSafe|IntegrityService|LicenseManager|Field Events|Division A|Series C)'
if command -v rg >/dev/null 2>&1; then
  RETIRED_MATCHES="$(rg -n "$RETIRED_PATTERN" Fotty project.yml Fotty.xcodeproj/project.pbxproj || true)"
else
  RETIRED_MATCHES="$(grep -REn "$RETIRED_PATTERN" Fotty project.yml Fotty.xcodeproj/project.pbxproj || true)"
fi
if [[ -n "$RETIRED_MATCHES" ]]; then
  printf '%s\n' "$RETIRED_MATCHES"
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
  "${CATALYST_BUILD_SETTINGS[@]}" \
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
  "${CATALYST_BUILD_SETTINGS[@]}" \
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
