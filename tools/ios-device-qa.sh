#!/usr/bin/env bash
# Physical-device release gate. It never starts a simulator or installs a UI-test runner.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_IDS=()
SKIP_DEPLOY=0
SKIP_RELEASE_BUILD=0
SKIP_TESTS=0
OWNS_DERIVED_DATA=0
XCODE_JOBS="${FOTTY_XCODE_JOBS:-2}"

if ! [[ "$XCODE_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FOTTY_XCODE_JOBS must be a positive integer." >&2
  exit 2
fi

if [[ -n "${FOTTY_RELEASE_GATE_DERIVED_DATA:-}" ]]; then
  RELEASE_GATE_DERIVED_DATA="$FOTTY_RELEASE_GATE_DERIVED_DATA"
elif [[ -n "${FOTTY_PHYSICAL_DEBUG_DERIVED_DATA:-}" ]]; then
  # Backward-compatible explicit override. The caller owns its lifecycle.
  RELEASE_GATE_DERIVED_DATA="$FOTTY_PHYSICAL_DEBUG_DERIVED_DATA"
else
  RELEASE_GATE_DERIVED_DATA="$(mktemp -d /private/tmp/FottyPhysicalReleaseGate.XXXXXX)"
  OWNS_DERIVED_DATA=1
fi

cleanup_derived_data() {
  [[ "$OWNS_DERIVED_DATA" -eq 1 ]] || return 0
  case "$RELEASE_GATE_DERIVED_DATA" in
    /private/tmp/FottyPhysicalReleaseGate.*)
      if [[ -e "$RELEASE_GATE_DERIVED_DATA" ]]; then
        find "$RELEASE_GATE_DERIVED_DATA" -depth -delete
      fi
      ;;
    *)
      echo "Refusing unexpected release-gate cleanup target: $RELEASE_GATE_DERIVED_DATA" >&2
      return 1
      ;;
  esac
}

trap cleanup_derived_data EXIT INT TERM

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

usage() {
  cat <<'EOF'
Usage: tools/ios-device-qa.sh [options]

Runs Fotty's no-simulator release gate:
  1. Full unit/policy tests on Mac Catalyst (no UI tests)
  2. Debug build, install, and launch of the normal Fotty app on each physical device
  3. The single production Release graph compiles for generic iOS
  4. Prints the manual iPhone/iPad checklist

Options:
  --device <udid>     Target physical device; repeat for iPhone and iPad
  --skip-deploy       Only run release build + print checklist
  --skip-release      Only deploy Debug
  --skip-tests        Skip the Mac Catalyst policy suite
  --help              Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_IDS+=("${2:-}"); shift 2 ;;
    --skip-deploy) SKIP_DEPLOY=1; shift ;;
    --skip-release) SKIP_RELEASE_BUILD=1; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

cd "$ROOT_DIR"

echo "Checking the season-labelled football reference catalog..."
node "$ROOT_DIR/tools/generate-football-competition-catalog.mjs" --check
echo "Checking deterministic and current provider football identities..."
node "$ROOT_DIR/tools/audit-provider-football-identity.mjs" --live

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  echo "Running the full policy suite on Mac Catalyst (no simulator, no UI tests)..."
  # Xcode 27 beta can strand a newly built Catalyst test host while waiting for
  # workers to materialize. Splitting compilation from execution is equivalent
  # coverage and has proven deterministic on this constrained workstation.
  xcodebuild build-for-testing \
    -quiet \
    -project "$ROOT_DIR/Fotty.xcodeproj" \
    -scheme Fotty \
    -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$RELEASE_GATE_DERIVED_DATA" \
    -jobs "$XCODE_JOBS" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:FottyTests
  xcodebuild test-without-building \
    -quiet \
    -project "$ROOT_DIR/Fotty.xcodeproj" \
    -scheme Fotty \
    -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$RELEASE_GATE_DERIVED_DATA" \
    -jobs "$XCODE_JOBS" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:FottyTests
fi

if [[ "$SKIP_DEPLOY" -eq 0 ]]; then
  PHYSICAL_DEBUG_DERIVED_DATA="$RELEASE_GATE_DERIVED_DATA"
  echo "Building one signed universal Debug artifact for every physical device..."
  xcodebuild \
    -quiet \
    -project "$ROOT_DIR/Fotty.xcodeproj" \
    -scheme Fotty \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$PHYSICAL_DEBUG_DERIVED_DATA" \
    -jobs "$XCODE_JOBS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    FOOTBALL_DATA_API_KEY= \
    RAPID_API_KEY= \
    API_FOOTBALL_KEY= \
    build

  PHYSICAL_APP_PATH="$PHYSICAL_DEBUG_DERIVED_DATA/Build/Products/Debug-iphoneos/Fotty.app"
  if [[ ! -d "$PHYSICAL_APP_PATH" ]]; then
    echo "Universal Debug app not found at $PHYSICAL_APP_PATH." >&2
    exit 1
  fi
  codesign --verify --deep --strict "$PHYSICAL_APP_PATH"

  if [[ "${#DEVICE_IDS[@]}" -eq 0 ]]; then
    "$ROOT_DIR/tools/ios-deploy-device.sh" --app-path "$PHYSICAL_APP_PATH"
  else
    for device_id in "${DEVICE_IDS[@]}"; do
      "$ROOT_DIR/tools/ios-deploy-device.sh" --device "$device_id" --app-path "$PHYSICAL_APP_PATH"
    done
  fi
fi

if [[ "$SKIP_RELEASE_BUILD" -eq 0 ]]; then
  echo ""
  echo "=== M0.4 Release build smoke ==="
  if rg -n '(APP_REVIEW_SAFE|ReviewSafe|Info-ReviewSafe|IntegrityService|LicenseManager|Field Events|Division A|Series C)' \
    "$ROOT_DIR/Fotty" \
    "$ROOT_DIR/project.yml" \
    "$ROOT_DIR/Fotty.xcodeproj/project.pbxproj"; then
    echo "Retired review-safe code or vocabulary is present in the production graph." >&2
    exit 1
  fi
  echo "Single product graph scan passed."
  xcodebuild \
    -project "$ROOT_DIR/Fotty.xcodeproj" \
    -scheme Fotty \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$RELEASE_GATE_DERIVED_DATA" \
    -jobs "$XCODE_JOBS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    -quiet \
    build
  echo "Release build succeeded."

fi

cat <<'EOF'

=== Physical iPhone/iPad checklist (archive Console logs for any failure) ===

[ ] Cold launch — Home is responsive for 60s and shows no watchdog termination
[ ] Home — all-sports Now & next and full lineup are unambiguous; real team badges remain visible; FPL stays in its own tab
[ ] Matchday — saved broadcasts and followed-team fixtures form the personal plan; saved channels stay separate
[ ] Match Center — score/status/data-quality labels are honest; Watch appears only with a source
[ ] Watch — source rows switch exactly when tapped; no unexplained risk/cooldown labels
[ ] Continuity — current stream survives one short network interruption without unsolicited replacement
[ ] Native handoff — a proven compatible source continues without a visible jump; unsuccessful handoff preserves the web source
[ ] Picture in Picture — PiP starts, keeps video visible outside Fotty, and returns to the same match
[ ] Background/foreground — no ticking audio, duplicate stream, or orphaned playback
[ ] Alerts/Live Activity — followed-team alert opens Match Center; Live Activity shows score/status and clears on close
[ ] FPL — Plan/Live/Review matches the official phase; snapshot metrics and Smart Coach evidence are current
[ ] Live FPL — official current and provisional totals remain separate; autosubs/captain fallback match the rules engine
[ ] Transfer Lab — Roll/one/two-move routes show weekly gain, cost, break-even, downside, checks, and local validation
[ ] Scenarios — named alternatives persist for this manager only and never imply an official submission
[ ] Coach — deterministic facts use zero tokens; model answers show evidence, downside, checks, freshness, source, and usage
[ ] Rival Race — post-deadline rival selection shows official gaps, captains, remaining players, and live-data provenance
[ ] Decision Journal — entries remain scoped to the current manager; the latest process lesson appears in the next Plan cycle
[ ] FPL widget — deadline and official-source label render at small/medium sizes; tap opens the FPL tab
[ ] Reminders — saving is silent; opt-in alert returns to the saved match without autoplay; removing it cancels the reminder
[ ] iPad — repeat rotation, source switching, PiP, and 60s foreground hold
[ ] Quality export — redacted JSON includes playback, football/FPL refresh, identity, and Coach summary without private data

Tips:
  - Unlock iPhone before deploy; trust this Mac if prompted.
  - For playback logs: filter Console by subsystem com.jelani.Fotty
  - Playback notices log via LivePlayerViewModel / FottyLogger stream_start
  - This gate intentionally never runs FottyUITests, so it cannot leave a UI-test runner app on a device.

Re-run deploy only:  tools/ios-deploy-device.sh
EOF
