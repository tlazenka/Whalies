#!/usr/bin/env bash
# Build and link an unsigned Release iOS archive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
  echo "Requires a Mac with Xcode and an iOS SDK." >&2
  exit 2
fi
if command -v xcodegen >/dev/null; then
  (cd Apps && xcodegen generate)
elif command -v mint >/dev/null; then
  (cd Apps && mint run xcodegen generate)
else
  echo "Install XcodeGen or Mint." >&2
  exit 2
fi
ARCHIVE_DIR="$ROOT/.build/WhaleyArchiveSmoke.xcarchive"
DERIVED_DIR="$ROOT/.build/WhaleyArchiveDerivedData"
xcodebuild -project Apps/Whaley.xcodeproj -scheme Whaley \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DIR" -archivePath "$ARCHIVE_DIR" \
  CODE_SIGNING_ALLOWED=NO archive

echo "Whaley Release archive built: $ARCHIVE_DIR"
