#!/bin/bash
# Runs every check: package tests, simulator build, privacy guard. Add --ui to run the UI tests too
# (they delete photos from the simulator library, so reseed afterwards with seed-simulator.sh).
set -uo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17}"
DESTINATION="platform=iOS Simulator,name=$SIM_NAME"
failed=0
step() { echo; echo "== $1"; }

step "CleanupCore tests (macOS host)"
if [ -d .fixtures ]; then export CLEANUP_FIXTURES="$PWD/.fixtures"; fi
(cd Packages/CleanupCore && swift test 2>&1 | grep -E "error:|✘|Test run" ) || failed=1
if [ -z "${CLEANUP_FIXTURES:-}" ]; then echo "note: CalibrationTests skipped, run scripts/fetch-fixtures.sh"; fi

step "Generate project and build for the simulator"
xcodegen generate >/dev/null || failed=1
build_log=$(xcodebuild -project PhotoCleanup.xcodeproj -scheme PhotoCleanup -destination "$DESTINATION" \
  -derivedDataPath build build 2>&1)
echo "$build_log" | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v "AppIntents" | sort -u
echo "$build_log" | grep -q "BUILD SUCCEEDED" || failed=1

step "Privacy guard"
./scripts/check-no-network.sh || failed=1

if [ "${1:-}" = "--ui" ]; then
  step "UI tests"
  xcodebuild -project PhotoCleanup.xcodeproj -scheme PhotoCleanup -destination "$DESTINATION" \
    -derivedDataPath build test 2>&1 | grep -E "error:|Test Case.*(passed|failed)|TEST (SUCCEEDED|FAILED)" || failed=1
fi

echo
[ "$failed" = 0 ] && echo "READY" || echo "NOT-READY"
exit $failed
