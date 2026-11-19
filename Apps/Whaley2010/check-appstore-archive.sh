#!/usr/bin/env bash
# Build and link an unsigned Release iOS archive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
    echo "This archive check requires macOS with Xcode." >&2
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

ARCHIVE="$ROOT/.build/Whaley2010AppStoreSmoke.xcarchive"
xcodebuild -project Apps/Whaley.xcodeproj -scheme Whaley2010 \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$ROOT/.build/Whaley2010ArchiveDerivedData" \
    -archivePath "$ARCHIVE" CODE_SIGNING_ALLOWED=NO archive

echo "Whaley2010 Release archive built: $ARCHIVE"
