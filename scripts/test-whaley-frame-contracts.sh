#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${CC:-clang}" -std=c11 -Wall -Wextra -Werror -pedantic \
  "$ROOT/scripts/tests/whaley-frame-geometry.c" -lm -o "$WORK/frames"
"$WORK/frames"
"${SWIFTC:-swiftc}" \
  "$ROOT/Sources/WhaleySpriteKit/SpriteFrameTimeline.swift" \
  "$ROOT/scripts/tests/whaley-frame-timeline.swift" -o "$WORK/timeline"
"$WORK/timeline"
