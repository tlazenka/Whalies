#!/usr/bin/env bash
# Compile the two consumers, execute the native contracts, and link real archives.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
  echo "Stadium integration requires a Mac with Xcode 27 and an iOS Simulator runtime." >&2
  exit 2
fi
command -v xcodegen >/dev/null || { echo "Install XcodeGen (brew install xcodegen)." >&2; exit 2; }
# Hostless Simulator tests load their bundles directly from DerivedData. Keep
# those products outside protected checkout locations such as ~/Documents.
# A stable suffix keeps separate checkouts from sharing one build database.
STADIUM_CHECKOUT_ID="$(printf '%s' "$ROOT" | shasum -a 256 | cut -c1-12)"
STADIUM_DERIVED_DATA_PATH="${STADIUM_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/WhaleyStadiumIntegration-$STADIUM_CHECKOUT_ID}"
mkdir -p "$STADIUM_DERIVED_DATA_PATH" .build/integration-logs
printf 'Integration DerivedData: %s\n' "$STADIUM_DERIVED_DATA_PATH"
printf '%s\n' "$STADIUM_DERIVED_DATA_PATH" > .build/integration-logs/derived-data-path.txt
xcodebuild -version
xcrun swift --version
(cd Apps && xcodegen generate)

swift test --package-path Apps/Stadium 2>&1 | tee .build/integration-logs/stadium-tests.log

SIMULATOR_ID="$(xcrun simctl list devices available --json | "${PYTHON:-python3}" "$ROOT/python/whaley.py" xcode simulator)"

xcodebuild -project Apps/Whaley.xcodeproj -scheme WhaleyCompatibilityTests \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$STADIUM_DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee .build/integration-logs/native-tests.log

xcodebuild -project Apps/Whaley.xcodeproj -scheme StadiumApp \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$STADIUM_DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee .build/integration-logs/stadium-simulator.log

xcodebuild -project Apps/Whaley.xcodeproj -scheme StadiumApp \
  -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$STADIUM_DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee .build/integration-logs/stadium-catalyst.log

for SCHEME in Whaley StadiumApp; do
  xcodebuild -project Apps/Whaley.xcodeproj -scheme "$SCHEME" \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$STADIUM_DERIVED_DATA_PATH" \
    -archivePath ".build/${SCHEME}Integration.xcarchive" \
    CODE_SIGNING_ALLOWED=NO archive 2>&1 | tee ".build/integration-logs/${SCHEME}-archive.log"
done
