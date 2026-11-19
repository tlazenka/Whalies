#!/usr/bin/env bash
# Run the real WhaleyCore 3D projection tests without downloading dependencies.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/Sources/WhaleyCore" "$TEMP/Tests/WhaleyCoreTests"
cp "$ROOT/Sources/WhaleyCore/WhaleySceneSnapshot.swift" "$TEMP/Sources/WhaleyCore/"
cp "$ROOT/Sources/WhaleyCore/WhaleyProjection3D.swift" "$TEMP/Sources/WhaleyCore/"
cp "$ROOT/Sources/WhaleyCore/WhaleyBubbleOptics.swift" "$TEMP/Sources/WhaleyCore/"
cp "$ROOT/Sources/WhaleyCore/Whaley3DJumpCamera.swift" "$TEMP/Sources/WhaleyCore/"
cp "$ROOT/Sources/WhaleyCore/Whaley3DHoldSession.swift" "$TEMP/Sources/WhaleyCore/"
cp "$ROOT/Sources/WhaleyCore/Whaley3DPressRouter.swift" "$TEMP/Sources/WhaleyCore/"
cp "$ROOT/Tests/WhaleyCoreTests/WhaleyProjection3DTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
cp "$ROOT/Tests/WhaleyCoreTests/WhaleyBubbleOpticsTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
cp "$ROOT/Tests/WhaleyCoreTests/Whaley3DJumpCameraTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
cp "$ROOT/Tests/WhaleyCoreTests/WhaleyVisiblePlayerTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
cp "$ROOT/Tests/WhaleyCoreTests/WhaleyAuthoritativeGeometryTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
cp "$ROOT/Tests/WhaleyCoreTests/Whaley3DHoldSessionTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
cp "$ROOT/Tests/WhaleyCoreTests/Whaley3DPressRouterTests.swift" "$TEMP/Tests/WhaleyCoreTests/"
clang -std=c11 -Wall -Wextra -Werror -I "$ROOT/Sources/WhaleyObjectiveC/include" \
    "$ROOT/Tests/WhaleyArenaRulesTests/snapshot_geometry.c" -lm -o "$TEMP/geometry-check"
"$TEMP/geometry-check"
clang -std=c11 -Wall -Wextra -Werror -I "$ROOT/Sources/WhaleyObjectiveC/include" \
    "$ROOT/Tests/WhaleyArenaRulesTests/shot_placement.c" -lm -o "$TEMP/shot-placement-check"
"$TEMP/shot-placement-check"
cat > "$TEMP/Package.swift" <<'SWIFTPM'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WhaleyProjection3DCheck",
    targets: [
        .target(name: "WhaleyCore"),
        .testTarget(name: "WhaleyCoreTests", dependencies: ["WhaleyCore"]),
    ]
)
SWIFTPM
swift test --package-path "$TEMP"
