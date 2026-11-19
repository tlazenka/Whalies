#!/usr/bin/env bash
# From WhaleKart: bash Apps/Whaley2010/check-ios-build.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# Catch absent original engine headers before Xcode invokes Clang.
bash Apps/Whaley2010/verify-engine.sh
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null; then
  echo "Xcode and the iOS SDK are required to build Whaley2010 (run on macOS)." >&2
  exit 2
fi
if command -v xcodegen >/dev/null; then
  (cd Apps && xcodegen generate)
elif command -v mint >/dev/null; then
  (cd Apps && mint run xcodegen generate)
else
  echo "Install XcodeGen (or Mint) before continuing." >&2
  exit 2
fi
xcodebuild \
  -project Apps/Whaley.xcodeproj \
  -scheme Whaley2010 \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ROOT/.build/Whaley2010DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
