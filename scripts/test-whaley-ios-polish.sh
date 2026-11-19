#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc "$ROOT/Sources/WhaleyHost/WhaleyHUDLayout.swift" \
  "$ROOT/scripts/tests/whaley-hud-layout.swift" -o "$WORK/hud-layout"
"$WORK/hud-layout"
