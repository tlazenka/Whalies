#!/bin/sh
# XcodeGen preflight for the historical cocos2d-backed Whaley2010 app.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/Packages/WhaleyCocos2D"
LEGACY="$ROOT/Apps/Whaley2010/Legacy"

for required in \
  "$PKG/Package.swift" \
  "$PKG/Sources/Cocos2D/cocos2d/cocos2d.h" \
  "$PKG/Sources/Cocos2D/cocos2d/CCLayer.h" \
  "$PKG/Sources/Cocos2D/cocos2d/Platforms/iOS/CCGLView.h" \
  "$PKG/Sources/Cocos2D/kazmath/include/kazmath/kazmath.h" \
  "$ROOT/Sources/WhaleyObjectiveC/src/WhaleyScene.m" \
  "$LEGACY/MainMenu.m"; do
  if [ ! -f "$required" ]; then
    echo "error: Whaley2010 required source is missing: $required" >&2
    echo "error: Ensure the WhaleyCocos2D package and the original Whaley2010 gameplay sources are present." >&2
    exit 1
  fi
done

echo "Whaley2010 package engine and gameplay sources found."
